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
    /// Supported procedural role, Model when absent/empty, or nil for unsupported source metadata.
    public let target: PartTarget?
    /// Exact ImportedModel archive role, separate from the editable procedural role choices.
    package let isImportedModel: Bool
    package var supportsMirroring: Bool { target == .model || isImportedModel }
    /// Known loop-interior fill flag, false when absent/empty, or nil for unsupported source text.
    /// Only stitching-loop geometry consumes this flag; it remains preserved for other roles.
    public let isLoopInteriorFilled: Bool?
    /// The effective mirror flag, or nil for unsupported source text.
    public let xMirrored: Bool?
    public let isVisible: Bool
    public let isLocked: Bool
    public let isDisabled: Bool
    /// Known cross-section selection (Quad when absent/empty), or nil for unsupported source metadata.
    /// Linked selections retain the exact source identity, including an unresolved imported target.
    public let cutFace: CutFaceSelection?
    /// Resolved archived part defaults and owned node overrides pointing to this Cut Face part.
    /// Other part roles report zero.
    public let cutFaceReferenceCount: Int
    /// Known finite rotation retained by the engine Float in half-turns (-1...1), zero by default, or nil when unsupported.
    public let cutRotation: Double?
    /// Known unified-deformation flag, false by default, or nil for unsupported source metadata.
    /// Unified deformation uses the part's maximum node radius on each nondefault scale direction.
    public let isDeformationUnified: Bool?
    private let materials: [PartMaterialProperty: Double]

    /// Read a finite supported material value without normalizing source metadata.
    /// - Parameter property: The existing metallic, roughness or glow field.
    /// - Returns: The source/default value in the reference UI range, or nil for unsupported metadata.
    /// - Example: `part.materialValue(.roughness)` reads surface roughness.
    public func materialValue(_ property: PartMaterialProperty) -> Double? { materials[property] }

    private let deformationScales: [PartDeformationProperty: Double]

    /// Read a supported cross-section scale without changing the source archive.
    /// - Parameter property: The width or thickness direction.
    /// - Returns: A finite scale from zero to two retained by the engine Float, one when absent, or nil for unsupported/ambiguous metadata.
    /// - Example: `part.deformationScale(.width)` reads the width factor.
    public func deformationScale(_ property: PartDeformationProperty) -> Double? { deformationScales[property] }

    private let modifiers: [PartModifierProperty: Bool]

    /// Read one modifier without changing its source representation.
    /// - Parameter property: The supported procedural flag.
    /// - Returns: The known source/default value, or nil for an unsupported or ambiguous source spelling.
    /// - Example: `part.modifierValue(.interpolation)` reads extra-ring generation.
    public func modifierValue(_ property: PartModifierProperty) -> Bool? { modifiers[property] }

    /// Whether the inherited engine can classify this exact identity as a linked cut-face target.
    /// Legacy non-UUID identities remain preserved but cannot be offered as new profile links.
    public var canBeCutFaceProfile: Bool { CutFaceLinks.canonicalID(id) != nil }

    /// Read the effective flag, including legacy defaults and spellings.
    public func state(_ property: PartStateProperty) -> Bool {
        switch property {
        case .visible: isVisible
        case .locked: isLocked
        case .disabled: isDisabled
        }
    }

    public var isEditVisible: Bool { isVisible && !isDisabled }
    public var isEditable: Bool { isEditVisible && !isLocked }

    init(
        id: String, name: String, index: Int, isVisible: Bool, isLocked: Bool, isDisabled: Bool,
        modifiers: [PartModifierProperty: Bool], deformationScales: [PartDeformationProperty: Double],
        isDeformationUnified: Bool?, cutFace: CutFaceSelection?, cutRotation: Double?, target: PartTarget?,
        isImportedModel: Bool,
        isLoopInteriorFilled: Bool?, materials: [PartMaterialProperty: Double], cutFaceReferenceCount: Int,
        xMirrored: Bool?
    ) {
        self.materials = materials
        self.isLoopInteriorFilled = isLoopInteriorFilled
        self.xMirrored = xMirrored
        self.target = target
        self.isImportedModel = isImportedModel
        self.cutFace = cutFace
        self.cutFaceReferenceCount = cutFaceReferenceCount
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
