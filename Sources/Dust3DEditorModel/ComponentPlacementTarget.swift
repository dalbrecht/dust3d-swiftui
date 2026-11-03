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

    /// Use the current selection when the grabbed row belongs to it, otherwise move that row alone.
    public init?(snapshot: EditorSnapshot, grabbedID: String) {
        guard snapshot.componentTree.rows.contains(where: { $0.id.utf8.elementsEqual(grabbedID.utf8) }) else {
            return nil
        }
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        ids =
            snapshot.selectedComponentIDs.contains(where: { $0.utf8.elementsEqual(grabbedID.utf8) })
            ? Array(snapshot.selectedComponentIDs) : [grabbedID]
    }

    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        context.isCurrent(in: snapshot)
    }
}
