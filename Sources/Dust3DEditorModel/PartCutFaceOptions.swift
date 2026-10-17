import Dust3DDocument

/// Pure menu choices that distinguish unsupported source state from selectable profiles.
public enum PartCutFaceOptions {
    /// Provide presets and the exact current linked profile, with a source placeholder only when needed.
    /// - Parameter current: Known source selection, or nil for unsupported metadata.
    /// - Returns: Unique choices in display order. Nil is a read-only source placeholder, never an edit command.
    /// - Example: `PartCutFaceOptions.selections(current: part.cutFace)`.
    public static func selections(current: CutFaceSelection?) -> [CutFaceSelection?] {
        let presets = CutFacePreset.allCases.map { Optional(CutFaceSelection.preset($0)) }
        if current == nil { return [nil] + presets }
        if case .linkedPart = current { return presets + [current] }
        return presets
    }
}
