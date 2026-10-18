/// Select a truthful compatibility notice for the representation actually being displayed.
public enum MaterialPreviewWarning {
    /// Retain fallback/unknown warnings and distinguish image support from legacy surface metadata.
    /// - Parameters:
    ///   - warning: Original pinned-engine warning, unchanged in the geometry value.
    ///   - hasBakedMaterials: Whether current material output is available to the viewport.
    ///   - hasLegacySurfaceDetails: Nonempty legacy surface attributes, or nil if source interpretation failed.
    /// - Returns: A remaining limitation, or nil when the known image limitation no longer applies.
    public static func message(
        _ warning: String, hasBakedMaterials: Bool, hasLegacySurfaceDetails: Bool?
    ) -> String? {
        guard !warning.isEmpty else { return nil }
        guard hasBakedMaterials else { return warning }
        switch warning {
        case "Untextured preview: image textures are not yet displayed.":
            return nil
        case "Untextured preview: image textures and procedural surface details are not yet displayed.":
            guard let hasLegacySurfaceDetails else { return "Procedural surface details could not be verified." }
            return hasLegacySurfaceDetails ? "Procedural surface details are not yet displayed." : nil
        default:
            return warning
        }
    }
}
