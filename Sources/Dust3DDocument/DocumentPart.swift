import Foundation

/// Supported part-state attributes, using the inherited XML names.
public enum PartStateProperty: String, CaseIterable, Sendable {
    case visible
    case locked
    case disabled
}

/// Immutable part metadata in source order. Visibility affects editing; disabled also excludes generation.
public struct DocumentPart: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let title: String
    public let isVisible: Bool
    public let isLocked: Bool
    public let isDisabled: Bool
    /// Known cross-section selection (Quad when absent/empty), or nil for unsupported source metadata.
    /// Linked selections retain the exact source identity, including an unresolved imported target.
    public let cutFace: CutFaceSelection?
    /// Known finite, non-subnormal rotation in half-turns (-1...1), zero by default, or nil when unsupported.
    public let cutRotation: Double?
    /// Known unified-deformation flag, false by default, or nil for unsupported source metadata.
    /// Unified deformation uses the part's maximum node radius on each nondefault scale direction.
    public let isDeformationUnified: Bool?
    private let deformationScales: [PartDeformationProperty: Double]

    /// Read a supported cross-section scale without changing the source archive.
    /// - Parameter property: The width or thickness direction.
    /// - Returns: A finite, non-subnormal scale from zero to two, one when absent, or nil for unsupported/ambiguous metadata.
    /// - Example: `part.deformationScale(.width)` reads the width factor.
    public func deformationScale(_ property: PartDeformationProperty) -> Double? { deformationScales[property] }

    private let modifiers: [PartModifierProperty: Bool]

    /// Read one modifier without changing its source representation.
    /// - Parameter property: The supported procedural flag.
    /// - Returns: The known source/default value, or nil for an unsupported or ambiguous source spelling.
    /// - Example: `part.modifierValue(.interpolation)` reads extra-ring generation.
    public func modifierValue(_ property: PartModifierProperty) -> Bool? { modifiers[property] }

    public var isEditVisible: Bool { isVisible && !isDisabled }
    public var isEditable: Bool { isEditVisible && !isLocked }

    init(
        id: String, name: String, index: Int, isVisible: Bool, isLocked: Bool, isDisabled: Bool,
        modifiers: [PartModifierProperty: Bool], deformationScales: [PartDeformationProperty: Double],
        isDeformationUnified: Bool?, cutFace: CutFaceSelection?, cutRotation: Double?
    ) {
        self.cutFace = cutFace
        self.cutRotation = cutRotation
        self.id = id
        self.name = name
        self.title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Part \(index + 1)" : name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.isDisabled = isDisabled
        self.deformationScales = deformationScales
        self.isDeformationUnified = isDeformationUnified
        self.modifiers = modifiers
    }
}
