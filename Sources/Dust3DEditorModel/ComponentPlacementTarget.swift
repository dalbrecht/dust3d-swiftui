import Dust3DDocument

/// Captures the selected components and editing context for a placement interaction.
public struct ComponentPlacementTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    let ids: [String]

    public init?(snapshot: EditorSnapshot) {
        guard !snapshot.selectedComponentIDs.isEmpty else { return nil }
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        ids = Array(snapshot.selectedComponentIDs)
    }

    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        context.isCurrent(in: snapshot)
    }
}
