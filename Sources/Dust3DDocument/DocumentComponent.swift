import Foundation

/// One component in XML preorder. Parent/child identities preserve the upstream nested hierarchy.
/// Unknown link kinds remain available without being interpreted as part references.
public struct DocumentComponent: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let parentID: String?
    public let childIDs: [String]
    public let linkDataType: String?
    public let linkData: String?
    /// A supported unlinked group, including an empty group. Unknown links remain opaque.
    public var isGroup: Bool { (linkDataType ?? "").isEmpty && (linkData ?? "").isEmpty }
    public var partID: String? { linkDataType == "partId" ? linkData : nil }
}

/// Component interpretation is opt-in: opaque hierarchies remain preservable by unrelated edits.
enum ComponentHierarchy {
    static func read(_ model: XMLDocument) throws -> [DocumentComponent] {
        let containers = model.rootElement()?.elements(forName: "components") ?? []
        guard containers.count <= 1 else { throw DocumentError.invalidComponent }
        let elements = PartSplitting.componentElements(model)
        guard elements.count <= 10_000 else { throw DocumentError.limitExceeded }
        // Upstream interprets any child tag with an ID as a component. Reject unknown tagged
        // identities rather than presenting a tree that silently omits generator input.
        for parent in containers + elements {
            for child in parent.children ?? [] {
                if let child = child as? XMLElement, child.name != "component",
                    child.attribute(forName: "id") != nil
                {
                    throw DocumentError.invalidComponent
                }
            }
        }
        var identities = Set<String>()
        var result: [DocumentComponent] = []
        for element in elements {
            guard let id = element.attribute(forName: "id")?.stringValue, !id.isEmpty,
                identities.insert(id).inserted
            else { throw DocumentError.invalidComponent }
            let parent = element.parent as? XMLElement
            result.append(
                DocumentComponent(
                    id: id,
                    name: element.attribute(forName: "name")?.stringValue ?? "",
                    parentID: parent?.name == "component" ? parent?.attribute(forName: "id")?.stringValue : nil,
                    childIDs: element.elements(forName: "component").compactMap {
                        $0.attribute(forName: "id")?.stringValue
                    },
                    linkDataType: element.attribute(forName: "linkDataType")?.stringValue,
                    linkData: element.attribute(forName: "linkData")?.stringValue))
        }
        return result
    }

    static func rename(_ model: XMLDocument, id: String, name: String) throws -> Bool {
        guard name.utf8.count <= 1024,
            name.unicodeScalars.allSatisfy({
                $0.value != 0xFFFE && $0.value != 0xFFFF && !CharacterSet.controlCharacters.contains($0)
                    && !CharacterSet.newlines.contains($0)
            })
        else { throw DocumentError.invalidComponentName }
        let components = try read(model)
        guard let component = components.first(where: { $0.id == id }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else { throw DocumentError.missingComponent(id) }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard component.name != value else { return false }
        element.removeAttribute(forName: "name")
        if !value.isEmpty {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "name"
            attribute.stringValue = value
            element.addAttribute(attribute)
        }
        return true
    }
}
