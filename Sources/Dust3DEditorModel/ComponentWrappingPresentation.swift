import Dust3DDocument

/// Pure group-wrapping presentation, independent of a window or rendering framework.
public struct ComponentWrappingPresentation: Equatable, Sendable {
    /// Linked and opaque components cannot own wrapping controls.
    public let isAvailable: Bool
    /// Only recognized active modes expose their parameter controls.
    public let showsSettings: Bool
    /// Ordered fields appropriate to the selected source mode.
    public let fields: [ComponentWrappingField]

    /// Derive visible controls without modifying document metadata.
    /// - Parameter component: Immutable component selected in the inspector.
    /// - Example: `ComponentWrappingPresentation(component: component).fields`.
    public init(component: DocumentComponent) {
        isAvailable = component.isGroup
        let properties: [ComponentWrappingScalarProperty]
        if component.isGroup, let mode = component.wrapping.mode, mode != ComponentWrapMode.none {
            showsSettings = true
            properties = mode == .cloth ? ComponentWrappingScalarProperty.allCases : [.offset, .smoothness]
        } else {
            showsSettings = false
            properties = []
        }
        fields = properties.map { ComponentWrappingField(property: $0) }
    }

    /// Display a recognized mode using a nonempty native menu label.
    /// - Parameter mode: Supported archive mode.
    /// - Returns: None, Skin or Cloth.
    /// - Example: `modeTitle(.none)` returns "None".
    public static func modeTitle(_ mode: ComponentWrapMode) -> String {
        switch mode {
        case .none: return "None"
        case .skin: return "Skin"
        case .cloth: return "Cloth"
        }
    }
}

/// One immutable scalar field and its user-facing range.
public struct ComponentWrappingField: Identifiable, Equatable, Sendable {
    /// The inherited geometry attribute edited by this field.
    public let property: ComponentWrappingScalarProperty
    /// Visible field caption.
    public let title: String
    /// Supported editing interval in concise display form.
    public let rangeDescription: String
    /// Stable identity across source-value and mode changes.
    public var id: ComponentWrappingScalarProperty { property }

    init(property: ComponentWrappingScalarProperty) {
        self.property = property
        switch property {
        case .offset: title = "Offset"
        case .smoothness: title = "Smoothness"
        case .drape: title = "Drape"
        case .drapeLength: title = "Drape length"
        case .openTop: title = "Open top"
        case .openBottom: title = "Open bottom"
        case .thickness: title = "Thickness"
        }
        rangeDescription = "0–\(property.bounds.upperBound)"
    }
}
