import Foundation

/// Existing scalar material fields, retaining the inherited archive names.
public enum PartMaterialProperty: String, CaseIterable, Sendable {
    case metallic
    case roughness
    case emissive

    /// Range offered by the reference editor; glow permits values up to two.
    public var bounds: ClosedRange<Double> { self == .emissive ? 0...2 : 0...1 }
    /// Inherited material value when the source attribute is absent.
    public var defaultValue: Double { self == .roughness ? 1 : 0 }
}

enum PartMaterial {
    static func values(_ element: XMLElement) -> [PartMaterialProperty: Double] {
        var values: [PartMaterialProperty: Double] = [:]
        for property in PartMaterialProperty.allCases {
            guard let text = element.attribute(forName: property.rawValue)?.stringValue else {
                values[property] = property.defaultValue
                continue
            }
            // Unsupported values remain source metadata until explicitly replaced.
            values[property] = EngineScalar.parse(text, in: property.bounds)
        }
        return values
    }

    static func set(
        _ model: XMLDocument, parts: [DocumentPart], id: String, property: PartMaterialProperty, value: Double
    ) throws -> Bool {
        guard EngineScalar.isValid(value, in: property.bounds) else { throw DocumentError.invalidPartMaterial }
        guard let current = parts.first(where: { $0.id == id }),
            let element = DocumentXML.childElements(model.rootElement(), named: "parts").first?
                .elements(forName: "part").first(where: { $0.attribute(forName: "id")?.stringValue == id })
        else { throw DocumentError.missingPart(id) }
        guard current.materialValue(property) != value else { return false }
        element.removeAttribute(forName: property.rawValue)
        if value != property.defaultValue {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = property.rawValue
            attribute.stringValue = String(value)
            element.addAttribute(attribute)
        }
        return true
    }
}
