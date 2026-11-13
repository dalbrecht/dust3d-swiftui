import Dust3DDocument
import Foundation

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

    /// Capture explicit context-menu rows independently of the sidebar's selection.
    package init?(snapshot: EditorSnapshot, componentIDs: Set<String>) {
        let rowIDs = Set(snapshot.componentTree.rows.map { Data($0.id.utf8) })
        guard !componentIDs.isEmpty, componentIDs.allSatisfy({ rowIDs.contains(Data($0.utf8)) }) else {
            return nil
        }
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        ids = Array(componentIDs)
    }

    package init?(snapshot: EditorSnapshot, singleComponentID: String) {
        self.init(snapshot: snapshot, componentIDs: [singleComponentID])
    }

    package func siblingPlacement(for move: ComponentOrderMove, in snapshot: EditorSnapshot) -> ComponentDropPlacement?
    {
        guard isCurrent(in: snapshot), let id = ids.first else { return nil }
        let rows = snapshot.componentTree.rows
        guard let row = rows.first(where: { $0.id.utf8.elementsEqual(id.utf8) }) else { return nil }
        let parent = row.component.parentID.map { Data($0.utf8) }
        let siblings = rows.filter { $0.component.parentID.map { Data($0.utf8) } == parent }
        let selection = Set(ids.map { Data($0.utf8) })
        let selectedPositions = siblings.indices.filter { selection.contains(Data(siblings[$0].id.utf8)) }
        guard selectedPositions.count == selection.count, let first = selectedPositions.first,
            let last = selectedPositions.last
        else { return nil }
        let unselected = siblings.indices.filter { !selection.contains(Data(siblings[$0].id.utf8)) }
        switch move {
        case .up: return unselected.last(where: { $0 < first }).map { .before(siblings[$0].id) }
        case .down: return unselected.first(where: { $0 > last }).map { .after(siblings[$0].id) }
        case .first: return unselected.first.map { .before(siblings[$0].id) }
        case .last: return unselected.last.map { .after(siblings[$0].id) }
        }
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
