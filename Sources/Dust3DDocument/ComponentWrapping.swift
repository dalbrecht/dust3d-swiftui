import Foundation

/// Inherited group wrapping modes. Unknown source modes remain uninterpreted.
public enum ComponentWrapMode: String, CaseIterable, Sendable {
    case none = ""
    case skin = "Skin"
    case cloth = "Cloth"
}

/// Geometry controls with the editing ranges of the inherited Qt inspector.
public enum ComponentWrappingScalarProperty: String, CaseIterable, Hashable, Sendable {
    case offset = "wrapOffset"
    case smoothness = "wrapSmoothness"
    case drape = "wrapDrape"
    case drapeLength = "wrapDrapeLength"
    case openTop = "wrapOpenTop"
    case openBottom = "wrapOpenBottom"
    case thickness = "wrapThickness"

    /// Supported explicit editing range in model units, except the dimensionless drape factor.
    public var bounds: ClosedRange<Double> {
        switch self {
        case .offset: return 0...0.1
        case .smoothness: return 0...0.15
        case .drape: return 0...1
        case .drapeLength: return 0...0.5
        case .openTop, .openBottom: return 0...0.45
        case .thickness: return 0...0.02
        }
    }

    /// Inherited default when this optional attribute is absent or empty.
    /// - Parameter mode: A recognized source mode; disabled wrapping uses Skin defaults.
    /// - Returns: The inherited scalar default.
    /// - Example: `ComponentWrappingScalarProperty.offset.defaultValue(for: .cloth)` returns 0.012.
    public func defaultValue(for mode: ComponentWrapMode) -> Double {
        switch self {
        case .offset: return mode == .cloth ? 0.012 : 0
        case .smoothness: return mode == .cloth ? 0.05 : 0.02
        case .drape: return mode == .cloth ? 0.5 : 0
        case .thickness: return mode == .cloth ? 0.004 : 0
        case .drapeLength, .openTop, .openBottom: return 0
        }
    }
}

/// Opt-in wrapping interpretation. Nil preserves unsupported source metadata without rewriting it.
public struct ComponentWrappingSettings: Equatable, Sendable {
    public let mode: ComponentWrapMode?
    /// Effective keep-children flag; absent/empty defaults to true only for Cloth.
    public let keepsChildren: Bool?
    /// Editable whole face count in 64...20000; larger engine-supported source values remain opaque.
    public let targetFaces: Int?
    private let scalars: [ComponentWrappingScalarProperty: Double]

    /// Read a supported explicit scalar or its mode-dependent default.
    /// - Parameter property: The geometry parameter to interpret.
    /// - Returns: A known value, or nil for unsupported metadata/unknown mode defaults.
    /// - Example: `component.wrapping.scalarValue(.offset)`.
    public func scalarValue(_ property: ComponentWrappingScalarProperty) -> Double? { scalars[property] }

    init(
        mode: ComponentWrapMode?, keepsChildren: Bool?, targetFaces: Int?,
        scalars: [ComponentWrappingScalarProperty: Double]
    ) {
        self.mode = mode
        self.keepsChildren = keepsChildren
        self.targetFaces = targetFaces
        self.scalars = scalars
    }
}

enum ComponentWrapping {
    static func read(_ element: XMLElement) -> ComponentWrappingSettings {
        let mode = ComponentWrapMode(rawValue: element.attribute(forName: "wrap")?.stringValue ?? "")
        let keep = element.attribute(forName: "wrapKeep")?.stringValue ?? ""
        let keepsChildren: Bool?
        if keep.isEmpty {
            keepsChildren = mode.map { $0 == .cloth }
        } else if ["true", "True", "1"].contains(keep) {
            keepsChildren = true
        } else if ["false", "False", "0"].contains(keep) {
            keepsChildren = false
        } else {
            keepsChildren = nil
        }
        let faces = element.attribute(forName: "wrapFaces")?.stringValue ?? ""
        let targetFaces: Int?
        if faces.isEmpty {
            targetFaces = mode.map { $0 == .cloth ? 1200 : 1600 }
        } else {
            targetFaces = Int(faces).flatMap { (64...20000).contains($0) ? $0 : nil }
        }
        var scalars: [ComponentWrappingScalarProperty: Double] = [:]
        for property in ComponentWrappingScalarProperty.allCases {
            let text = element.attribute(forName: property.rawValue)?.stringValue ?? ""
            scalars[property] =
                text.isEmpty
                ? mode.map { property.defaultValue(for: $0) } : EngineScalar.parse(text, in: property.bounds)
        }
        return ComponentWrappingSettings(
            mode: mode, keepsChildren: keepsChildren, targetFaces: targetFaces, scalars: scalars)
    }

    static func setMode(_ model: XMLDocument, id: String, mode: ComponentWrapMode) throws -> Bool {
        let (current, element) = try group(model, id: id)
        guard current.mode != mode else { return false }
        replace(element, name: "wrap", value: mode == .none ? nil : mode.rawValue)
        return true
    }
    static func setKeep(_ model: XMLDocument, id: String, value: Bool) throws -> Bool {
        let (current, element) = try group(model, id: id)
        guard current.keepsChildren != value else { return false }
        let isDefault = current.mode.map { ($0 == .cloth) == value } ?? false
        replace(element, name: "wrapKeep", value: isDefault ? nil : value ? "true" : "false")
        return true
    }
    static func setFaces(_ model: XMLDocument, id: String, faces: Int) throws -> Bool {
        guard (64...20000).contains(faces) else { throw DocumentError.invalidComponentWrapping }
        let (current, element) = try group(model, id: id)
        guard current.targetFaces != faces else { return false }
        let isDefault = current.mode.map { ($0 == .cloth ? 1200 : 1600) == faces } ?? false
        replace(element, name: "wrapFaces", value: isDefault ? nil : String(faces))
        return true
    }
    static func setScalar(_ model: XMLDocument, id: String, property: ComponentWrappingScalarProperty, value: Double)
        throws -> Bool
    {
        guard EngineScalar.isValid(value, in: property.bounds) else { throw DocumentError.invalidComponentWrapping }
        let (current, element) = try group(model, id: id)
        guard current.scalarValue(property) != value else { return false }
        let isDefault = current.mode.map { property.defaultValue(for: $0) == value } ?? false
        replace(element, name: property.rawValue, value: isDefault ? nil : String(value))
        return true
    }
    private static func group(_ model: XMLDocument, id: String) throws -> (ComponentWrappingSettings, XMLElement) {
        guard let current = try ComponentHierarchy.read(model).first(where: { $0.id == id }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else { throw DocumentError.missingComponent(id) }
        guard current.isGroup else { throw DocumentError.invalidComponentWrapping }
        return (current.wrapping, element)
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
