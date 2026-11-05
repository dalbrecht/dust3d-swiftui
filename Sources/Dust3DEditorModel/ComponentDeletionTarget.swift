import Dust3DDocument
import Foundation

/// An explicit sidebar selection or contextual row set, independent of the earlier model selection.
public struct ComponentDeletionTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    let ids: [String]
    /// Number of outermost explicit subtree roots, with selected descendants counted only once.
    public let rootCount: Int

    /// Capture literal row identities and all document, revision, selection and constraint epochs.
    /// - Parameters: snapshot is the originating window; componentIDs supplies contextual rows, or nil for current selection.
    /// - Example: `ComponentDeletionTarget(snapshot: snapshot, componentIDs: [rightClickedRowID])`.
    public init(snapshot: EditorSnapshot, componentIDs: [String]? = nil) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        let requested = componentIDs ?? Array(snapshot.selectedComponentIDs)
        let indexed = Dictionary(
            uniqueKeysWithValues: snapshot.componentTree.rows.map { (Data($0.id.utf8), $0.component) })
        guard !requested.isEmpty, requested.count <= 10_000,
            requested.allSatisfy({ indexed[Data($0.utf8)] != nil })
        else {
            ids = []
            rootCount = 0
            return
        }
        let keys = Set(requested.map { Data($0.utf8) })
        let identities = snapshot.componentTree.rows.filter { keys.contains(Data($0.id.utf8)) }.map(\.id)
        ids = identities
        // Visit a selected descendant closure once, rather than walking a shared ancestor chain per row.
        var closure = Set<Data>()
        var pending = Array(keys)
        while let key = pending.popLast() {
            guard closure.insert(key).inserted else { continue }
            pending.append(contentsOf: indexed[key]?.childIDs.map { Data($0.utf8) } ?? [])
        }
        rootCount =
            identities.filter { id in
                indexed[Data(id.utf8)]?.parentID.map { closure.contains(Data($0.utf8)) } != true
            }.count
    }
    /// Whether the captured intent still belongs to the same unchanged window context.
    /// - Parameter snapshot: The current actor or UI snapshot.
    /// - Returns: False for initially unavailable targets and every document/selection/constraint ABA change.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        !ids.isEmpty && context.isCurrent(in: snapshot)
    }
}

/// A stale menu or key callback cannot delete a later document or component selection.
public enum ComponentDeletionError: Error, Equatable, Sendable { case staleTarget }

extension EditorState {
    /// Delete the explicit captured row subtrees, including locked/hidden/disabled owned graph parts.
    /// - Parameter target: An admitted sidebar context; canvas interaction locks do not redefine management intent.
    /// - Throws: Stale target, cancellation or original document preflight errors without partial publication.
    /// - Example: `try state.deleteComponentSubtrees(target: target)`.
    public mutating func deleteComponentSubtrees(target: ComponentDeletionTarget) throws {
        try Task.checkCancellation()
        guard target.isCurrent(in: snapshot) else { throw ComponentDeletionError.staleTarget }
        var next = self
        try next.apply([.removeComponentSubtrees(target.ids)])
        try Task.checkCancellation()
        self = next
    }
}
