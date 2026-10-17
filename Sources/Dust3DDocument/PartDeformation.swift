import Foundation

/// Cross-section scale properties using the inherited archive attribute names.
public enum PartDeformationProperty: String, CaseIterable, Sendable {
    /// Scale along the generated cross-section's width direction.
    case width = "deformWidth"
    /// Scale along the generated cross-section's thickness direction.
    case thickness = "deformThickness"
}

enum PartDeformation {
    static func scales(_ element: XMLElement) -> [PartDeformationProperty: Double] {
        var values: [PartDeformationProperty: Double] = [:]
        for property in PartDeformationProperty.allCases {
            guard let text = element.attribute(forName: property.rawValue)?.stringValue else {
                values[property] = 1
                continue
            }
            if let value = EngineScalar.parse(text, in: 0...2) { values[property] = value }
            // Empty scales differ between Qt import and core generation; preserve ambiguous metadata.
        }
        return values
    }

    static func unified(_ element: XMLElement) -> Bool? {
        guard let text = element.attribute(forName: "deformUnified")?.stringValue else { return false }
        if ["true", "True", "1"].contains(text) { return true }
        if ["false", "False", "0", ""].contains(text) { return false }
        return nil
    }

    static func setScale(
        _ model: XMLDocument, parts: [DocumentPart], id: String, property: PartDeformationProperty, value: Double
    ) throws -> Bool {
        guard EngineScalar.isValid(value, in: 0...2) else { throw DocumentError.invalidPartDeformation }
        let (current, element) = try part(model, parts: parts, id: id)
        guard current.deformationScale(property) != value else { return false }
        // Qt omits values within 0.01 of one; retain explicit nondefaults to avoid losing fine edits.
        replaceAttribute(element, name: property.rawValue, value: value == 1 ? nil : String(value))
        return true
    }

    static func setUnified(_ model: XMLDocument, parts: [DocumentPart], id: String, value: Bool) throws -> Bool {
        let (current, element) = try part(model, parts: parts, id: id)
        guard current.isDeformationUnified != value else { return false }
        replaceAttribute(element, name: "deformUnified", value: value ? "true" : nil)
        return true
    }

    private static func part(_ model: XMLDocument, parts: [DocumentPart], id: String) throws -> (
        DocumentPart, XMLElement
    ) {
        guard let current = parts.first(where: { $0.id == id }),
            let element = DocumentXML.childElements(model.rootElement(), named: "parts").first?
                .elements(forName: "part").first(where: { $0.attribute(forName: "id")?.stringValue == id })
        else { throw DocumentError.missingPart(id) }
        return (current, element)
    }

    private static func replaceAttribute(_ element: XMLElement, name: String, value: String?) {
        element.removeAttribute(forName: name)
        guard let value else { return }
        let attribute = XMLNode(kind: .attribute)
        attribute.name = name
        attribute.stringValue = value
        element.addAttribute(attribute)
    }
}
