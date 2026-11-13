/// Absolute cross-section orientations matching the Qt inspector's quick actions.
package enum PartCutRotationPreset: Int, CaseIterable, Sendable {
    case negativeQuarterTurn = -90
    case zero = 0
    case positiveQuarterTurn = 90

    package var halfTurns: Double { Double(rawValue) / 180 }
}

extension EditorSnapshot {
    /// Match the Part inspector's explicit selection and shared linked-part routes.
    package func cutRotationPresets(for partID: String) -> [PartCutRotationPreset] {
        guard selectedComponent == nil, let part = selectedPart ?? selectedLinkedComponentPart,
            part.id.utf8.elementsEqual(partID.utf8)
        else { return [] }
        if part.isImportedModel { return [.zero] }
        return part.target == .model ? PartCutRotationPreset.allCases : []
    }
}
