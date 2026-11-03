import Foundation

/// One immutable context per structural element; relative base references retain their FULL ancestor chain.
private struct UngroupContexts {
    private struct BaseStep: Hashable {
        let parent: Int
        let reference: Data
    }
    struct Context {
        var language: Data?
        var space = Data("default".utf8)
        var base = 0
        var namespaceEnvironment = 0
    }
    private var bases: [BaseStep: Int] = [:]
    private var cached: [ObjectIdentifier: Context] = [:]
    private struct NamespaceFrame {
        let parent: Int?
        let bindings: [Data: DocumentXML.NamespaceBinding]
    }
    private struct EnvironmentPair: Hashable {
        let source: Int
        let destination: Int
    }
    private var frames = [NamespaceFrame(parent: nil, bindings: [Data(): ("", "")])]
    private var differences: [EnvironmentPair: [DocumentXML.NamespaceBinding]] = [:]
    private var materializationBudget = DocumentXML.NamespaceBudget()
    // Explicit work units matching the 16 MiB model envelope; no unbounded namespace search.
    private var remainingNamespaceWork = 16 * 1024 * 1024

    mutating func original(_ element: XMLElement) -> Context {
        if let value = cached[ObjectIdentifier(element)] { return value }
        var pending: [XMLElement] = []
        var cursor: XMLElement? = element
        while let node = cursor, cached[ObjectIdentifier(node)] == nil {
            pending.append(node)
            cursor = node.parent as? XMLElement
        }
        var value = cursor.flatMap { cached[ObjectIdentifier($0)] } ?? Context()
        for node in pending.reversed() {
            value = applying(node, to: value)
            cached[ObjectIdentifier(node)] = value
        }
        return value
    }

    mutating func applying(_ element: XMLElement, to parent: Context, namespaces: Bool = true) -> Context {
        var value = parent
        if let text = element.attribute(forName: "xml:lang")?.stringValue {
            value.language = text.isEmpty ? nil : Data(text.utf8)
        }
        if let text = element.attribute(forName: "xml:space")?.stringValue { value.space = Data(text.utf8) }
        if let text = element.attribute(forName: "xml:base")?.stringValue {
            // Exact absolute references prove independence of prior bases. Unproven syntax and ALL
            // relative references remain ordered tokens; no URI resolution, rewriting or network access.
            let step = BaseStep(parent: Self.isAbsoluteReference(text) ? 0 : parent.base, reference: Data(text.utf8))
            if let known = bases[step] {
                value.base = known
            } else {
                let next = bases.count + 1
                bases[step] = next
                value.base = next
            }
        }
        if namespaces {
            let local = Dictionary(
                uniqueKeysWithValues: (element.namespaces ?? []).map {
                    (Data(($0.name ?? "").utf8), (prefix: $0.name ?? "", uri: $0.stringValue ?? ""))
                })
            if !local.isEmpty {
                frames.append(NamespaceFrame(parent: parent.namespaceEnvironment, bindings: local))
                value.namespaceEnvironment = frames.count - 1
            }
        }
        return value
    }

    private mutating func consumeNamespaceWork() throws {
        guard remainingNamespaceWork > 0 else { throw DocumentError.limitExceeded }
        remainingNamespaceWork -= 1
    }
    private mutating func lookup(_ prefix: Data, in environment: Int) throws -> String? {
        var cursor: Int? = environment
        while let index = cursor {
            try consumeNamespaceWork()
            if let binding = frames[index].bindings[prefix] { return binding.uri }
            cursor = frames[index].parent
        }
        return nil
    }
    mutating func namespaceDifference(from oldParent: XMLElement, to destination: XMLElement) throws
        -> [DocumentXML.NamespaceBinding]
    {
        let sourceEnvironment = original(oldParent).namespaceEnvironment
        let destinationEnvironment = original(destination).namespaceEnvironment
        let pair = EnvironmentPair(source: sourceEnvironment, destination: destinationEnvironment)
        let candidates: [DocumentXML.NamespaceBinding]
        if let known = differences[pair] {
            candidates = known
        } else {
            var output: [DocumentXML.NamespaceBinding] = []
            var seen = Set<Data>()
            var cursor = sourceEnvironment
            // Promotion is ancestor-only: stop at the shared lexical environment. No full
            // inherited map is retained for unrelated or nonmoved nodes.
            while cursor != destinationEnvironment {
                try consumeNamespaceWork()
                let frame = frames[cursor]
                guard let parent = frame.parent else { throw DocumentError.invalidComponentStructure }
                for (prefix, binding) in frame.bindings.sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) {
                    try consumeNamespaceWork()
                    guard seen.insert(prefix).inserted else { continue }
                    if try lookup(prefix, in: destinationEnvironment)?.utf8.elementsEqual(binding.uri.utf8) != true {
                        try materializationBudget.reserve([binding])
                        output.append(binding)
                    }
                }
                cursor = parent
            }
            differences[pair] = output
            candidates = output
        }
        return candidates
    }
    mutating func bindingsToPreserve(_ element: XMLElement, movingTo destination: XMLElement) throws
        -> [DocumentXML.NamespaceBinding]
    {
        guard let oldParent = element.parent as? XMLElement else { throw DocumentError.invalidComponentStructure }
        let candidates = try namespaceDifference(from: oldParent, to: destination)
        let local = Set((element.namespaces ?? []).map { Data(($0.name ?? "").utf8) })
        return candidates.filter { !local.contains(Data($0.prefix.utf8)) }
    }

    private static func isAbsoluteReference(_ text: String) -> Bool {
        // Strict parsing must not percent-encode invalid source into a fabricated absolute reset.
        guard let uri = URLComponents(string: text, encodingInvalidCharacters: false),
            uri.scheme != nil, uri.fragment == nil
        else { return false }
        return true
    }

}

enum ComponentUngroupBatch {
    private struct Update {
        let parent: XMLElement
        let children: [XMLNode]
    }
    private struct Move {
        let node: XMLNode
        let parent: XMLElement
        let owner: String
    }

    static func apply(_ model: XMLDocument, ids: [String]) throws -> Bool {
        guard ids.count <= ComponentUngroupPlan.maximumCount else { throw DocumentError.limitExceeded }
        guard !ids.isEmpty else { return false }
        let components = try ComponentHierarchy.read(model)
        let plan = try ComponentUngroupPlan(components: components, ids: ids)
        guard !plan.wrapperIDs.isEmpty else { return false }
        let elements = PartSplitting.componentElements(model)
        let selected = Set(plan.wrapperIDs.map { Data($0.utf8) })
        let wrappers = Set(
            zip(components, elements).filter { selected.contains(Data($0.0.id.utf8)) }
                .map { ObjectIdentifier($0.1) })
        let names = Dictionary(
            uniqueKeysWithValues: zip(components, elements).map { (ObjectIdentifier($0.1), $0.0.id) })
        guard let container = DocumentXML.childElements(model.rootElement(), named: "components").first else {
            throw DocumentError.invalidComponentStructure
        }
        var contexts = UngroupContexts()
        for element in [container] + elements { _ = contexts.original(element) }
        var updates: [Update] = []
        var moves: [Move] = []
        // A selected wrapper is expanded once by its final surviving parent. Surviving nested
        // parents have their OWN child list processed once, without caching repeated flattened arrays.
        for parent in [container] + elements where !wrappers.contains(ObjectIdentifier(parent)) {
            var pending = Array((parent.children ?? []).reversed())
            var output: [XMLNode] = []
            var changed = false
            while let node = pending.popLast() {
                if let element = node as? XMLElement, wrappers.contains(ObjectIdentifier(element)) {
                    pending.append(contentsOf: (element.children ?? []).reversed())
                    changed = true
                } else {
                    output.append(node)
                    if node.parent !== parent {
                        guard let originalParent = node.parent as? XMLElement,
                            let owner = names[ObjectIdentifier(originalParent)]
                        else {
                            throw DocumentError.invalidComponentStructure
                        }
                        moves.append(Move(node: node, parent: parent, owner: owner))
                    }
                }
            }
            if changed { updates.append(Update(parent: parent, children: output)) }
        }
        // Each moved surviving root must retain its context. If a destination itself moves, it
        // is checked too; unchanged-context induction makes its original context a sound reference.
        for move in moves {
            guard let oldParent = move.node.parent as? XMLElement else { throw DocumentError.invalidComponentStructure }
            let destination = contexts.original(move.parent)
            let before: UngroupContexts.Context
            let after: UngroupContexts.Context
            if let element = move.node as? XMLElement {
                before = contexts.original(element)
                after = contexts.applying(element, to: destination, namespaces: false)
            } else {
                before = contexts.original(oldParent)
                after = destination
            }
            let attribute: String?
            if before.language != after.language {
                attribute = "xml:lang"
            } else if before.space != after.space {
                attribute = "xml:space"
            } else if before.base != after.base {
                attribute = "xml:base"
            } else {
                attribute = nil
            }
            if let attribute {
                throw ComponentUngroupError.inheritedContext(componentID: move.owner, attribute: attribute)
            }
        }
        for move in moves
        where move.node.kind == .text
            && (move.node.stringValue ?? "").utf8.contains(where: {
                $0 != 0x09 && $0 != 0x0A && $0 != 0x0D && $0 != 0x20
            })
        {
            guard let oldParent = move.node.parent as? XMLElement else { throw DocumentError.invalidComponentStructure }
            // Text/CDATA cannot carry a hoisted namespace declaration. Its opaque content is not
            // parsed or rewritten to guess whether a binding matters; reject a changed environment.
            if try !contexts.namespaceDifference(from: oldParent, to: move.parent).isEmpty {
                throw ComponentUngroupError.textNamespaceContext(componentID: move.owner)
            }
        }
        var budget = DocumentXML.NamespaceBudget()
        for move in moves {
            guard let element = move.node as? XMLElement else { continue }
            let bindings = try contexts.bindingsToPreserve(element, movingTo: move.parent)
            try budget.install(bindings, on: element)
        }
        try Task.checkCancellation()
        for update in updates { for child in update.parent.children ?? [] { child.detach() } }
        for update in updates { for child in update.children { child.detach() } }
        for update in updates { for child in update.children { update.parent.addChild(child) } }
        try Task.checkCancellation()
        return true
    }
}
