import Foundation

// XML stays separate so the public color value has no framework dependencies.
extension ComponentColorValue {
    static func read(_ element: XMLElement) -> ComponentColorValue {
        guard let text = element.attribute(forName: "color")?.stringValue else { return .unset }
        return DocumentColor(archiveValue: text).map(ComponentColorValue.value) ?? .unsupported(text)
    }

    static func set(_ model: XMLDocument, id: String, color: DocumentColor?) throws -> Bool {
        let components = try ComponentHierarchy.read(model)
        guard let current = components.first(where: { $0.id == id }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else { throw DocumentError.missingComponent(id) }
        let next = color.map(ComponentColorValue.value) ?? .unset
        guard current.color != next else { return false }
        element.removeAttribute(forName: "color")
        if let color {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "color"
            attribute.stringValue = color.archiveValue
            element.addAttribute(attribute)
        }
        return true
    }
}
