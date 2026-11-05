import Foundation

/// Supported world-space coat patterns. Unknown archive text remains uninterpreted.
public enum ComponentSurfacePattern: String, CaseIterable, Sendable {
    case none = ""
    case spots = "Spots"
    case rosettes = "Rosettes"
    case stripes = "Stripes"
    case patches = "Patches"
    case mottled = "Mottled"
}

/// Surface-bake parameters with the inherited Qt editing ranges and defaults.
public enum ComponentSurfaceScalar: String, CaseIterable, Hashable, Sendable {
    case patternScale = "wrapPatternScale"
    case belly = "wrapBelly"
    case wrinkles = "wrapWrinkles"
    case wrinkleSize = "wrapWrinkleSize"

    /// Admitted explicit edits; source values outside this interval stay opaque until replaced.
    public var bounds: ClosedRange<Double> {
        switch self {
        case .patternScale: return 0.01...0.3
        case .belly, .wrinkles: return 0...1
        case .wrinkleSize: return 0.2...4
        }
    }
    /// Inherited value used when the attribute is absent or empty.
    public var defaultValue: Double {
        switch self {
        case .patternScale: return 0.06
        case .belly, .wrinkles: return 0
        case .wrinkleSize: return 1
        }
    }
}

/// Lossless opt-in interpretation of wrap finish metadata, independent of the active wrap mode.
public struct ComponentSurfaceDetails: Equatable, Sendable {
    public let pattern: ComponentSurfacePattern?
    /// Automatic ink, recognized opaque RGB, or exact unsupported source text.
    public let ink: ComponentColorValue
    private let scalars: [ComponentSurfaceScalar: Double]

    /// Read a supported scalar or its default without rewriting its original spelling.
    /// - Parameter property: The finish parameter to interpret.
    /// - Returns: Nil for unsupported explicit source text.
    /// - Example: `component.wrapping.surfaceDetails.scalarValue(.wrinkles)`.
    public func scalarValue(_ property: ComponentSurfaceScalar) -> Double? { scalars[property] }

    static func read(_ element: XMLElement) -> Self {
        let pattern = ComponentSurfacePattern(rawValue: element.attribute(forName: "wrapPattern")?.stringValue ?? "")
        let color = element.attribute(forName: "wrapPatternColor")?.stringValue ?? ""
        let ink: ComponentColorValue
        if color.isEmpty {
            ink = .unset
        } else if let value = DocumentColor(archiveValue: color), value.alpha == 255 {
            ink = .value(value)
        } else {
            ink = .unsupported(color)
        }
        var scalars: [ComponentSurfaceScalar: Double] = [:]
        for property in ComponentSurfaceScalar.allCases {
            let text = element.attribute(forName: property.rawValue)?.stringValue ?? ""
            scalars[property] = text.isEmpty ? property.defaultValue : EngineScalar.parse(text, in: property.bounds)
        }
        return Self(pattern: pattern, ink: ink, scalars: scalars)
    }
}

/// Only the requested attribute changes; disabling wrapping never destroys retained finish settings.
enum ComponentSurfaceMetadata {
    static func pattern(_ model: XMLDocument, id: String, pattern: ComponentSurfacePattern) throws -> Bool {
        let (current, element) = try group(model, id: id)
        guard current.pattern != pattern else { return false }
        replace(element, name: "wrapPattern", value: pattern == .none ? nil : pattern.rawValue)
        return true
    }
    static func scalar(_ model: XMLDocument, id: String, property: ComponentSurfaceScalar, value: Double) throws -> Bool
    {
        guard EngineScalar.isValid(value, in: property.bounds) else { throw DocumentError.invalidComponentWrapping }
        let (current, element) = try group(model, id: id)
        guard current.scalarValue(property) != value else { return false }
        replace(element, name: property.rawValue, value: value == property.defaultValue ? nil : String(value))
        return true
    }
    static func color(_ model: XMLDocument, id: String, color: DocumentColor?) throws -> Bool {
        guard color == nil || color?.alpha == 255 else { throw DocumentError.invalidComponentWrapping }
        let (current, element) = try group(model, id: id)
        guard current.ink != color.map(ComponentColorValue.value) ?? .unset else { return false }
        replace(element, name: "wrapPatternColor", value: color?.archiveValue)
        return true
    }
    private static func group(_ model: XMLDocument, id: String) throws -> (ComponentSurfaceDetails, XMLElement) {
        guard let component = try ComponentHierarchy.read(model).first(where: { $0.id == id }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else { throw DocumentError.missingComponent(id) }
        guard component.isGroup else { throw DocumentError.invalidComponentWrapping }
        return (component.wrapping.surfaceDetails, element)
    }
    private static func replace(_ element: XMLElement, name: String, value: String?) {
        element.removeAttribute(forName: name)
        guard let value else { return }
        let attribute = XMLNode(kind: .attribute)
        attribute.name = name
        attribute.stringValue = value
        element.addAttribute(attribute)
    }
}
