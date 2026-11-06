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
    /// Exact imported body-reference text, including empty, missing and unsupported targets.
    public let binding: ComponentWrapBindingValue
    /// Effective keep-children flag; absent/empty defaults to true only for Cloth.
    public let keepsChildren: Bool?
    /// Editable whole face count in 64...20000; larger engine-supported source values remain opaque.
    public let targetFaces: Int?
    /// Retained pattern and wrinkle settings; active effects are baked through the material pipeline.
    public let surfaceDetails: ComponentSurfaceDetails
    private let scalars: [ComponentWrappingScalarProperty: Double]

    /// Read a supported explicit scalar or its mode-dependent default.
    /// - Parameter property: The geometry parameter to interpret.
    /// - Returns: A known value, or nil for unsupported metadata/unknown mode defaults.
    /// - Example: `component.wrapping.scalarValue(.offset)`.
    public func scalarValue(_ property: ComponentWrappingScalarProperty) -> Double? { scalars[property] }

    init(
        mode: ComponentWrapMode?, keepsChildren: Bool?, targetFaces: Int?,
        scalars: [ComponentWrappingScalarProperty: Double], surfaceDetails: ComponentSurfaceDetails,
        binding: ComponentWrapBindingValue
    ) {
        self.mode = mode
        self.keepsChildren = keepsChildren
        self.targetFaces = targetFaces
        self.scalars = scalars
        self.surfaceDetails = surfaceDetails
        self.binding = binding
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
            mode: mode, keepsChildren: keepsChildren, targetFaces: targetFaces, scalars: scalars,
            surfaceDetails: .read(element),
            binding: (element.attribute(forName: "wrapBindTo")?.stringValue).map(ComponentWrapBindingValue.stored)
                ?? .absent)
    }

    static func setMode(_ model: XMLDocument, id: String, mode: ComponentWrapMode) throws -> Bool {
        try ComponentWrappingBatch.apply(model, ids: [id], edit: .mode(mode))
    }
    static func setKeep(_ model: XMLDocument, id: String, value: Bool) throws -> Bool {
        try ComponentWrappingBatch.apply(model, ids: [id], edit: .keepChildren(value))
    }
    static func setFaces(_ model: XMLDocument, id: String, faces: Int) throws -> Bool {
        try ComponentWrappingBatch.apply(model, ids: [id], edit: .targetFaces(faces))
    }
    static func setScalar(_ model: XMLDocument, id: String, property: ComponentWrappingScalarProperty, value: Double)
        throws -> Bool
    {
        try ComponentWrappingBatch.apply(model, ids: [id], edit: .scalar(property, value))
    }
}
