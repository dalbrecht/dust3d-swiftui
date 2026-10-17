import Foundation

/// Supported procedural part flags, serialized with inherited XML attribute names.
public enum PartModifierProperty: String, CaseIterable, Sendable {
    /// Subdivide the cross-section template before generating the part.
    case subdivision = "subdived"
    /// Chamfer the cross-section template before generating the part.
    case chamfer = "chamfered"
    /// Round the front and back ends of the part.
    case roundedEnds = "rounded"
    /// Generate extra rings along long edges; enabled by default.
    case interpolation = "interpolated"
    /// Use crisp boolean joins instead of smooth blending.
    case hardJoin = "hard"

    /// Inherited default when the attribute is absent.
    public var defaultValue: Bool { self == .interpolation }
}

enum PartModifiers {
    static func values(_ element: XMLElement) -> [PartModifierProperty: Bool] {
        var values: [PartModifierProperty: Bool] = [:]
        for property in PartModifierProperty.allCases {
            guard let text = element.attribute(forName: property.rawValue)?.stringValue else {
                values[property] = property.defaultValue
                continue
            }
            if ["true", "True", "1"].contains(text) {
                values[property] = true
            } else if ["false", "False", "0"].contains(text) || (text.isEmpty && property != .interpolation) {
                values[property] = false
            }
            // Empty interpolation differs between Qt import and core generation; preserve it as unavailable metadata.
        }
        return values
    }

    static func set(
        _ model: XMLDocument, parts: [DocumentPart], id: String, property: PartModifierProperty, value: Bool
    ) throws -> Bool {
        guard let current = parts.first(where: { $0.id == id }),
            let part = DocumentXML.childElements(model.rootElement(), named: "parts").first?
                .elements(forName: "part").first(where: { $0.attribute(forName: "id")?.stringValue == id })
        else { throw DocumentError.missingPart(id) }
        guard current.modifierValue(property) != value else { return false }
        part.removeAttribute(forName: property.rawValue)
        if value != property.defaultValue {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = property.rawValue
            attribute.stringValue = value ? "true" : "false"
            part.addAttribute(attribute)
        }
        return true
    }
}
