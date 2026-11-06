/// Select truthful notices from retained geometry and the current accepted material output.
public enum MaterialPreviewWarning {
    /// Combine diagnostics without granting a legacy bake imported-model capabilities.
    /// - Parameters:
    ///   - warning: Original geometry warning, preserved in its owner.
    ///   - hasBakedMaterials: Current procedural material GPU frame was acknowledged.
    ///   - hasImportedMaterials: Current imported-material GPU frame was acknowledged.
    ///   - hasSourceBakedMaterials: Current source-aware GPU frame applies its imported and procedural surfaces.
    ///   - hasLegacySurfaceDetails: Retained legacy detail attributes, or nil if source interpretation failed.
    ///   - hasRenderedSurfaceDetails: A matching legacy-baked frame confirms procedural surface details only.
    ///   - materialWarning: Diagnostic from current accepted preparation, including after GPU failure; never stale output.
    /// - Returns: Remaining notices, with byte-exact unknown causes and capability-specific limitations.
    /// - Example: `message(warning, hasBakedMaterials: true, hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true)`.
    public static func message(
        _ warning: String, hasBakedMaterials: Bool, hasImportedMaterials: Bool = false,
        hasSourceBakedMaterials: Bool = false, hasLegacySurfaceDetails: Bool?,
        hasRenderedSurfaceDetails: Bool = false, materialWarning: String? = nil
    ) -> String? {
        let ordinary = ordinaryMessage(
            warning, hasBakedMaterials: hasBakedMaterials,
            hasImportedMaterials: hasImportedMaterials, hasSourceBakedMaterials: hasSourceBakedMaterials,
            hasLegacySurfaceDetails: hasLegacySurfaceDetails, hasRenderedSurfaceDetails: hasRenderedSurfaceDetails)
        let prepared = materialWarning.flatMap {
            preparedMessage(
                $0, hasBakedMaterials: hasBakedMaterials, hasImportedMaterials: hasImportedMaterials,
                hasSourceBakedMaterials: hasSourceBakedMaterials, hasLegacySurfaceDetails: hasLegacySurfaceDetails,
                hasRenderedSurfaceDetails: hasRenderedSurfaceDetails)
        }
        guard let ordinary else { return prepared }
        guard let prepared else { return ordinary }
        if ordinary.utf8.elementsEqual(prepared.utf8) { return ordinary }
        if extends(prepared, original: ordinary) { return prepared }
        if extends(ordinary, original: prepared) { return ordinary }
        return ordinary + "\n" + prepared
    }

    private static func extends(_ message: String, original: String) -> Bool {
        guard message.utf8.starts(with: original.utf8),
            let separator = message.utf8.dropFirst(original.utf8.count).first
        else { return false }
        return [32, 10, 13, 9].contains(separator)
    }

    private static func preparedMessage(
        _ warning: String, hasBakedMaterials: Bool, hasImportedMaterials: Bool,
        hasSourceBakedMaterials: Bool, hasLegacySurfaceDetails: Bool?, hasRenderedSurfaceDetails: Bool
    ) -> String? {
        var obsolete: [String] = []
        if hasSourceBakedMaterials || (hasBakedMaterials && hasRenderedSurfaceDetails) {
            obsolete.append("Untextured preview: image textures and procedural surface details are not yet displayed.")
        }
        if hasBakedMaterials || hasSourceBakedMaterials {
            obsolete.append("Untextured preview: image textures are not yet displayed.")
        }
        if hasImportedMaterials || hasSourceBakedMaterials {
            obsolete.append("Imported geometry preview: GLB materials, textures and transparency are not yet applied.")
        }
        var remaining = warning
        // Only standalone leading notices describe capabilities; an unknown remainder is opaque.
        while let notice = obsolete.first(where: {
            remaining.utf8.elementsEqual($0.utf8) || extends(remaining, original: $0)
        }) {
            remaining.removeFirst(notice.count)
            while let first = remaining.utf8.first, [32, 10, 13, 9].contains(first) { remaining.removeFirst() }
        }
        guard !remaining.isEmpty else { return nil }
        let image = "Untextured preview: image textures are not yet displayed."
        let surface = "Untextured preview: image textures and procedural surface details are not yet displayed."
        let imported = "Imported geometry preview: GLB materials, textures and transparency are not yet applied."
        let recognized = [image, surface, imported, image + " " + imported, surface + " " + imported]
        // The suffix processor applies only to complete recognized notices, never to an opaque remaining cause.
        guard recognized.contains(where: { remaining.utf8.elementsEqual($0.utf8) }) else { return remaining }
        return ordinaryMessage(
            remaining, hasBakedMaterials: hasBakedMaterials,
            hasImportedMaterials: hasImportedMaterials, hasSourceBakedMaterials: hasSourceBakedMaterials,
            hasLegacySurfaceDetails: hasLegacySurfaceDetails, hasRenderedSurfaceDetails: hasRenderedSurfaceDetails)
    }

    private static func ordinaryMessage(
        _ warning: String, hasBakedMaterials: Bool, hasImportedMaterials: Bool,
        hasSourceBakedMaterials: Bool, hasLegacySurfaceDetails: Bool?, hasRenderedSurfaceDetails: Bool
    ) -> String? {
        guard !warning.isEmpty else { return nil }
        var remaining = warning
        let imported = "Imported geometry preview: GLB materials, textures and transparency are not yet applied."
        if (hasImportedMaterials || hasSourceBakedMaterials) && remaining.hasSuffix(imported) {
            remaining.removeLast(imported.count)
            while remaining.last?.isWhitespace == true { remaining.removeLast() }
        }
        guard !remaining.isEmpty else { return nil }
        guard hasBakedMaterials || hasSourceBakedMaterials else {
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
        let surfaceNotice = "Untextured preview: image textures and procedural surface details are not yet displayed."
        if hasBakedMaterials && hasRenderedSurfaceDetails {
            if remaining == surfaceNotice { return nil }
            // A legacy bake proves procedural details, never the separately inherited imported-material limitation.
            if remaining == surfaceNotice + " " + imported { return imported }
        }
        switch remaining {
        case "Untextured preview: image textures are not yet displayed.":
            return nil
        case "Untextured preview: image textures and procedural surface details are not yet displayed.":
            if hasSourceBakedMaterials { return nil }
            guard let hasLegacySurfaceDetails else { return "Procedural surface details could not be verified." }
            return hasLegacySurfaceDetails ? "Procedural surface details are not yet displayed." : nil
        default:
            return remaining
        }
    }
}
