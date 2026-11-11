import Dust3DDocument
import Foundation

/// Captures the selected components and editing context for a placement interaction.
public struct ComponentPlacementTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    package let ids: [String]

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

    /// Capture an explicit context-menu row independently of the sidebar's selection.
    package init?(snapshot: EditorSnapshot, singleComponentID: String) {
        guard snapshot.componentTree.rows.contains(where: { $0.id.utf8.elementsEqual(singleComponentID.utf8) })
        else { return nil }
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        ids = [singleComponentID]
    }

    package func siblingPlacement(for move: ComponentOrderMove, in snapshot: EditorSnapshot) -> ComponentDropPlacement?
    {
        guard isCurrent(in: snapshot), ids.count == 1, let id = ids.first else { return nil }
        let rows = snapshot.componentTree.rows
        guard let row = rows.first(where: { $0.id.utf8.elementsEqual(id.utf8) }) else { return nil }
        let parent = row.component.parentID.map { Data($0.utf8) }
        let siblings = rows.filter { $0.component.parentID.map { Data($0.utf8) } == parent }
        guard let index = siblings.firstIndex(where: { $0.id.utf8.elementsEqual(id.utf8) }),
            let destination = move.destinationIndex(from: index, count: siblings.count)
        else { return nil }
        let anchor = siblings[destination].id
        return destination < index ? .before(anchor) : .after(anchor)
    }

    package func groupCenterSiblingPlacement(anchorID: String, in snapshot: EditorSnapshot) -> ComponentDropPlacement? {
        guard isCurrent(in: snapshot),
            let anchor = snapshot.componentTree.rows.first(where: { $0.id.utf8.elementsEqual(anchorID.utf8) })
        else { return nil }
        let parent = anchor.component.parentID.map { Data($0.utf8) }
        let siblings = snapshot.componentTree.rows.filter { $0.component.parentID.map { Data($0.utf8) } == parent }
        let selection = Set(ids.map { Data($0.utf8) })
        let selectedPositions = siblings.indices.filter { selection.contains(Data(siblings[$0].id.utf8)) }
        guard selectedPositions.count == selection.count, let last = selectedPositions.last,
            let anchorPosition = siblings.firstIndex(where: { $0.id.utf8.elementsEqual(anchorID.utf8) })
        else { return nil }
        let placement: ComponentDropPlacement = anchorPosition > last ? .after(anchor.id) : .before(anchor.id)
        return canPlace(at: placement, in: snapshot) ? placement : nil
    }

    public func canPlace(at placement: ComponentDropPlacement, in snapshot: EditorSnapshot) -> Bool {
        guard isCurrent(in: snapshot) else { return false }
        let plan = try? ComponentDropPlacementPlan(
            components: snapshot.componentTree.rows.map(\.component), ids: ids, placement: placement)
        return plan?.changesOrder == true
    }

    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        context.isCurrent(in: snapshot)
    }
}
