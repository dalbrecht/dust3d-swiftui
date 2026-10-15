import Foundation

/// Immutable selected-node fragment. Assets are included to preserve opaque extension references.
/// Construct with `Dust3DDocument.copyingNodes`; imported fragments are validated by this initializer.
public struct NodeClipboard: Sendable {
    public let document: Dust3DDocument
    public let selectedNodeIDs: Set<String>
    /// Semantic identities in document order; supply one fresh ID for each when pasting.
    public let identifiers: [String]

    public init(document: Dust3DDocument, selectedNodeIDs: Set<String>) throws {
        let contents = try document.editorContents()
        guard !selectedNodeIDs.isEmpty, selectedNodeIDs.isSubset(of: Set(contents.nodes.map(\.id))),
            contents.nodes.allSatisfy({ $0.partID != nil })
        else { throw DocumentError.invalidNode }
        let model = try XMLDocument(data: document.modelXML, options: [.nodePreserveAll])
        guard (model.rootElement()?.elements(forName: "components").count ?? 0) <= 1 else {
            throw DocumentError.invalidNode
        }
        let elements = NodeClipboardMutation.semanticElements(model)
        let ids = elements.compactMap { $0.attribute(forName: "id")?.stringValue }
        guard ids.count == elements.count, Set(ids.map { CutFaceLinks.canonicalID($0) ?? $0 }).count == ids.count,
            ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
            model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part").count ?? 0 <= 10_000,
            PartSplitting.componentElements(model).count <= 10_000
        else { throw DocumentError.invalidNode }
        let parts = model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part") ?? []
        let partIDs = Set(parts.compactMap { $0.attribute(forName: "id")?.stringValue })
        let nodesByID = Dictionary(uniqueKeysWithValues: contents.nodes.map { ($0.id, $0) })
        let edgeElements = model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge") ?? []
        for edge in edgeElements {
            if let partID = edge.attribute(forName: "partId")?.stringValue,
                let from = edge.attribute(forName: "from")?.stringValue
            {
                guard nodesByID[from]?.partID == partID else { throw DocumentError.invalidNode }
            }
        }
        var degree: [String: Int] = [:]
        var pairs = Set<Set<String>>()
        for edge in contents.edges {
            guard edge.fromID != edge.toID, nodesByID[edge.fromID]?.partID == nodesByID[edge.toID]?.partID,
                pairs.insert([edge.fromID, edge.toID]).inserted
            else {
                throw DocumentError.invalidNode
            }
            degree[edge.fromID, default: 0] += 1
            degree[edge.toID, default: 0] += 1
        }
        guard degree.values.allSatisfy({ $0 <= 2 }),
            PartSplitting.componentElements(model).allSatisfy({ component in
                component.attribute(forName: "linkDataType")?.stringValue != "partId"
                    || partIDs.contains(component.attribute(forName: "linkData")?.stringValue ?? "")
            })
        else { throw DocumentError.invalidNode }
        try PartJoining.validateProfileLinks(
            parts: parts, nodes: model.rootElement()?.elements(forName: "nodes").first?.elements(forName: "node") ?? [])
        self.document = document
        self.selectedNodeIDs = selectedNodeIDs
        self.identifiers = ids
    }
}

/// Structural traversal deliberately excludes component-like unknown extension elements.
enum NodeClipboardMutation {
    static func semanticElements(_ model: XMLDocument) -> [XMLElement] {
        guard let root = model.rootElement() else { return [] }
        return ["nodes", "edges", "parts"].flatMap { name in
            root.elements(forName: name).first?.elements(forName: String(name.dropLast())) ?? []
        } + PartSplitting.componentElements(model)
    }

    /// Detached subtrees must carry bindings inherited from their former ancestors.
    static func preserveNamespaces(_ element: XMLElement) {
        var bindings: [String: String] = [:]
        var ancestor: XMLNode? = element
        while let current = ancestor {
            if let current = current as? XMLElement {
                for namespace in current.namespaces ?? [] {
                    let prefix = namespace.name ?? ""
                    if bindings[prefix] == nil { bindings[prefix] = namespace.stringValue ?? "" }
                }
            }
            ancestor = current.parent
        }
        if bindings[""] == nil { bindings[""] = "" }
        let local = Set((element.namespaces ?? []).map { $0.name ?? "" })
        for (prefix, uri) in bindings.sorted(by: { $0.key < $1.key }) where !local.contains(prefix) {
            let namespace = XMLNode(kind: .namespace)
            namespace.name = prefix
            namespace.stringValue = uri
            element.addNamespace(namespace)
        }
    }

    static func extract(_ selected: Set<String>, model: XMLDocument, contents: DocumentContents) throws {
        guard !selected.isEmpty, selected.isSubset(of: Set(contents.nodes.map(\.id))),
            contents.nodes.filter({ selected.contains($0.id) }).allSatisfy({ $0.partID != nil }),
            let root = model.rootElement()
        else { throw DocumentError.invalidNode }
        let nodes = root.elements(forName: "nodes").first?.elements(forName: "node") ?? []
        let parts = root.elements(forName: "parts").first?.elements(forName: "part") ?? []
        let knownParts = try CutFaceLinks.index(parts.compactMap { $0.attribute(forName: "id")?.stringValue })
        var includedNodes = selected
        var includedParts = Set(contents.nodes.filter { selected.contains($0.id) }.compactMap(\.partID))
        let nodesByPart = Dictionary(grouping: nodes, by: { $0.attribute(forName: "partId")?.stringValue ?? "" })
        let partsByID = Dictionary(
            uniqueKeysWithValues: parts.compactMap { part in
                part.attribute(forName: "id")?.stringValue.map { ($0, part) }
            })
        var pending =
            nodes.filter { selected.contains($0.attribute(forName: "id")?.stringValue ?? "") }
            + includedParts.compactMap { partsByID[$0] }
        var completeProfiles = Set<String>()
        // Each included node and part is queued once, including profiles reached after partial selection.
        while let element = pending.popLast() {
            guard let target = CutFaceLinks.target(element.attribute(forName: "cutFace")?.stringValue, in: knownParts)
            else {
                continue
            }
            if includedParts.insert(target).inserted, let part = partsByID[target] { pending.append(part) }
            guard completeProfiles.insert(target).inserted else { continue }
            for node in nodesByPart[target] ?? [] {
                if let id = node.attribute(forName: "id")?.stringValue, includedNodes.insert(id).inserted {
                    pending.append(node)
                }
            }
        }
        for node in nodes where !includedNodes.contains(node.attribute(forName: "id")?.stringValue ?? "") {
            node.detach()
        }
        for edge in root.elements(forName: "edges").first?.elements(forName: "edge") ?? [] {
            if !includedNodes.contains(edge.attribute(forName: "from")?.stringValue ?? "")
                || !includedNodes.contains(edge.attribute(forName: "to")?.stringValue ?? "")
            {
                edge.detach()
            }
        }
        for part in parts where !includedParts.contains(part.attribute(forName: "id")?.stringValue ?? "") {
            part.detach()
        }
        func retain(_ component: XMLElement) -> Bool {
            var hasChildren = false
            for child in component.elements(forName: "component") {
                if retain(child) { hasChildren = true } else { child.detach() }
            }
            let linked = component.attribute(forName: "linkDataType")?.stringValue == "partId"
            let matches = linked && includedParts.contains(component.attribute(forName: "linkData")?.stringValue ?? "")
            if linked && !matches && hasChildren {
                component.removeAttribute(forName: "linkData")
                component.removeAttribute(forName: "linkDataType")
            }
            return matches || hasChildren
        }
        for component in root.elements(forName: "components").first?.elements(forName: "component") ?? [] {
            if !retain(component) { component.detach() }
        }
        for element in (root.children ?? []).compactMap({ $0 as? XMLElement })
        where !["nodes", "edges", "parts", "components"].contains(element.name ?? "") { element.detach() }
        try PartJoining.validateProfileLinks(
            parts: root.elements(forName: "parts").first?.elements(forName: "part") ?? [],
            nodes: root.elements(forName: "nodes").first?.elements(forName: "node") ?? [])
    }

    static func paste(
        _ clipboard: NodeClipboard, identities: [String: String], offset: NodePosition,
        into model: XMLDocument, contents: DocumentContents
    ) throws {
        let fragment = try XMLDocument(data: clipboard.document.modelXML, options: [.nodePreserveAll])
        guard let root = model.rootElement(), let sourceRoot = fragment.rootElement(),
            Set(identities.keys) == Set(clipboard.identifiers),
            Set(identities.values.map { CutFaceLinks.canonicalID($0) ?? $0 }).count == identities.count,
            identities.values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
            [offset.x, offset.y, offset.z].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 })
        else { throw DocumentError.invalidNode }
        guard root.elements(forName: "components").count <= 1 else { throw DocumentError.invalidNode }
        let existingElements = semanticElements(model)
        let existingIDs = existingElements.compactMap { $0.attribute(forName: "id")?.stringValue }
        let existing = Set(existingIDs.map { CutFaceLinks.canonicalID($0) ?? $0 })
        guard existingIDs.count == existingElements.count, existing.count == existingIDs.count,
            existing.isDisjoint(with: identities.values.map { CutFaceLinks.canonicalID($0) ?? $0 })
        else { throw DocumentError.invalidNode }
        let added = try clipboard.document.editorContents()
        guard contents.nodes.count + added.nodes.count <= 10_000, contents.edges.count + added.edges.count <= 20_000,
            (root.elements(forName: "parts").first?.elements(forName: "part").count ?? 0)
                + (sourceRoot.elements(forName: "parts").first?.elements(forName: "part").count ?? 0) <= 10_000,
            PartSplitting.componentElements(model).count + PartSplitting.componentElements(fragment).count <= 10_000
        else { throw DocumentError.limitExceeded }
        let addedNodes = Dictionary(uniqueKeysWithValues: added.nodes.map { ($0.id, $0.value) })
        let addedParts = try CutFaceLinks.index(
            sourceRoot.elements(forName: "parts").first?.elements(forName: "part").compactMap {
                $0.attribute(forName: "id")?.stringValue
            } ?? [])
        for element in semanticElements(fragment) {
            let name = element.name
            let originalID = element.attribute(forName: "id")?.stringValue ?? ""
            let keys: [String]
            switch name {
            case "node": keys = ["id", "partId"]
            case "edge": keys = ["id", "partId", "from", "to"]
            case "part": keys = ["id"]
            default: keys = ["id"]
            }
            for key in keys {
                if let attribute = element.attribute(forName: key), let value = attribute.stringValue,
                    let replacement = identities[value]
                {
                    attribute.stringValue = replacement
                }
            }
            if name == "node" || name == "part",
                let attribute = element.attribute(forName: "cutFace"),
                let target = CutFaceLinks.target(attribute.stringValue, in: addedParts),
                let replacement = identities[target]
            {
                guard CutFaceLinks.canonicalID(replacement) != nil else { throw DocumentError.invalidNode }
                attribute.stringValue = replacement
            }
            if name == "component", element.attribute(forName: "linkDataType")?.stringValue == "partId",
                let attribute = element.attribute(forName: "linkData"), let value = attribute.stringValue,
                let replacement = identities[value]
            {
                attribute.stringValue = replacement
            }
            if name == "node", let value = addedNodes[originalID] {
                let position = value.position
                let moved = EditableNode(
                    position: .init(x: position.x + offset.x, y: position.y + offset.y, z: position.z + offset.z),
                    radius: value.radius)
                guard moved.isValid else { throw DocumentError.invalidNode }
                for (key, number) in [("x", moved.position.x), ("y", moved.position.y), ("z", moved.position.z)] {
                    element.attribute(forName: key)?.stringValue = String(number == 0 ? 0 : number)
                }
            }
        }
        let transfers = [("nodes", "node"), ("edges", "edge"), ("parts", "part"), ("components", "component")].map {
            container, element in
            (container, sourceRoot.elements(forName: container).first?.elements(forName: element) ?? [])
        }
        let incoming = semanticElements(fragment)
        let semanticObjects = Set(incoming.map { ObjectIdentifier($0) })
        for element in incoming {
            preserveNamespaces(element)
            for child in (element.children ?? []).compactMap({ $0 as? XMLElement })
            where !semanticObjects.contains(ObjectIdentifier(child)) { preserveNamespaces(child) }
        }
        // Native graph objects join the destination canvas namespace; opaque extensions keep theirs.
        for element in incoming {
            element.removeNamespace(forPrefix: "")
            let namespace = XMLNode(kind: .namespace)
            namespace.name = ""
            namespace.stringValue = root.uri ?? ""
            element.addNamespace(namespace)
            element.uri = root.uri
        }
        for (containerName, children) in transfers {
            let container: XMLElement
            if let existing = root.elements(forName: containerName).first {
                container = existing
            } else {
                container = XMLElement(name: containerName)
                root.addChild(container)
            }
            for child in children {
                preserveNamespaces(child)
                child.detach()
                container.addChild(child)
            }
        }
        try PartJoining.validateProfileLinks(
            parts: root.elements(forName: "parts").first?.elements(forName: "part") ?? [],
            nodes: root.elements(forName: "nodes").first?.elements(forName: "node") ?? [])
    }
}
