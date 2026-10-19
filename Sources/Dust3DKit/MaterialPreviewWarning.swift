/// Select a truthful compatibility notice for the representation actually being displayed.
public enum MaterialPreviewWarning {
    /// Retain fallback/unknown warnings and distinguish image support from legacy surface metadata.
    /// - Parameters:
    ///   - warning: Original pinned-engine warning, unchanged in the geometry value.
    ///   - hasBakedMaterials: Whether current material output is available to the viewport.
    ///   - hasImportedMaterials: A current imported-material GPU frame was acknowledged.
    ///   - hasLegacySurfaceDetails: Nonempty legacy surface attributes, or nil if source interpretation failed.
    /// - Returns: A remaining limitation, or nil when the known image limitation no longer applies.
    public static func message(
        _ warning: String, hasBakedMaterials: Bool, hasImportedMaterials: Bool = false, hasLegacySurfaceDetails: Bool?
    ) -> String? {
        guard !warning.isEmpty else { return nil }
        var remaining = warning
        let imported = "Imported geometry preview: GLB materials, textures and transparency are not yet applied."
        if hasImportedMaterials && remaining.hasSuffix(imported) {
            remaining.removeLast(imported.count)
            while remaining.last?.isWhitespace == true { remaining.removeLast() }
        }
        guard !remaining.isEmpty else { return nil }
        guard hasBakedMaterials else {
            if hasImportedMaterials {
                switch remaining {
                case "Untextured preview: image textures are not yet displayed.":
                    return "Component image textures are not yet displayed."
                case "Untextured preview: image textures and procedural surface details are not yet displayed.":
                    return "Component image textures and surface details are not yet displayed."
                default: break
                }
            }
            return remaining
        }
        switch remaining {
        case "Untextured preview: image textures are not yet displayed.":
            return nil
        case "Untextured preview: image textures and procedural surface details are not yet displayed.":
            guard let hasLegacySurfaceDetails else { return "Procedural surface details could not be verified." }
            return hasLegacySurfaceDetails ? "Procedural surface details are not yet displayed." : nil
        default:
            return remaining
        }
    }
}
