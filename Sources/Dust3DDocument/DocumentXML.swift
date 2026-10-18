import Foundation

/// Shared XML identity and namespace policy for clipboard transfers and structural component edits.
enum DocumentXML {
    // Namespace-aware Foundation lookups can omit a moved child with a different default namespace.
    // Match qualified tags, preserving the native format while excluding prefixed extension tags.
    static func childElements(_ parent: XMLElement?, named name: String) -> [XMLElement] {
        (parent?.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name == name }
    }

    static func semanticElements(_ model: XMLDocument) -> [XMLElement] {
        guard let root = model.rootElement() else { return [] }
        return ["nodes", "edges", "parts"].flatMap { name in
            childElements(childElements(root, named: name).first, named: String(name.dropLast()))
        } + PartSplitting.componentElements(model)
    }

    typealias NamespaceBinding = (prefix: String, uri: String)

    /// One operation owns a cumulative quota before inherited bindings become new XML nodes.
    struct NamespaceBudget {
        private var remainingBindings = 100_000
        private var remainingBytes = 16 * 1024 * 1024

        init() {}

        mutating func preserve(_ element: XMLElement, movingTo destination: XMLElement? = nil) throws {
            try install(DocumentXML.namespaceBindingsToPreserve(element, movingTo: destination), on: element)
        }

        mutating func install(_ bindings: [NamespaceBinding], on element: XMLElement) throws {
            guard bindings.count <= remainingBindings else { throw DocumentError.limitExceeded }
            var available = remainingBytes
            for binding in bindings {
                guard available >= 16, binding.prefix.utf8.count <= available - 16 else {
                    throw DocumentError.limitExceeded
                }
                available -= 16 + binding.prefix.utf8.count
                guard binding.uri.utf8.count <= available else { throw DocumentError.limitExceeded }
                available -= binding.uri.utf8.count
            }
            remainingBindings -= bindings.count
            remainingBytes = available
            DocumentXML.installNamespaces(bindings, on: element)
        }
    }

    static func namespaceBindingsToPreserve(_ element: XMLElement, movingTo destination: XMLElement?)
        -> [NamespaceBinding]
    {
        let bindings = inheritedBindings(of: element)
        let target = destination.map { inheritedBindings(of: $0) }
        let local = Set((element.namespaces ?? []).map { $0.name ?? "" })
        return bindings.sorted(by: { $0.key < $1.key }).filter {
            !local.contains($0.key) && target?[$0.key] != $0.value
        }.map { (prefix: $0.key, uri: $0.value) }
    }

    private static func installNamespaces(_ bindings: [NamespaceBinding], on element: XMLElement) {
        for (prefix, uri) in bindings {
            let namespace = XMLNode(kind: .namespace)
            namespace.name = prefix
            namespace.stringValue = uri
            element.addNamespace(namespace)
        }
    }

    private static func inheritedBindings(of element: XMLElement) -> [String: String] {
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
        return bindings
    }
}
