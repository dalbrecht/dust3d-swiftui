import Foundation

enum PartLoopInterior {
    static func value(_ element: XMLElement) -> Bool? {
        let text = element.attribute(forName: "fillLoopInterior")?.stringValue ?? ""
        if ["true", "True", "1"].contains(text) { return true }
        if ["false", "False", "0", ""].contains(text) { return false }
        return nil
    }

    static func set(_ model: XMLDocument, parts: [DocumentPart], id: String, value: Bool) throws -> Bool {
        guard let current = parts.first(where: { $0.id == id }),
            let element = DocumentXML.childElements(model.rootElement(), named: "parts").first?
                .elements(forName: "part").first(where: { $0.attribute(forName: "id")?.stringValue == id })
        else { throw DocumentError.missingPart(id) }
        guard current.isLoopInteriorFilled != value else { return false }
        element.removeAttribute(forName: "fillLoopInterior")
        if value {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "fillLoopInterior"
            attribute.stringValue = "true"
            element.addAttribute(attribute)
        }
        return true
    }
}
