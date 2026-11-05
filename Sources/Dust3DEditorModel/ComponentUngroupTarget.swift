import Dust3DDocument
import Foundation

/// One explicit contextual row set or raw sidebar selection; no document XML is parsed on the UI actor.
public struct ComponentUngroupTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    let ids: [String]
    /// Number of actual wrappers, including explicitly selected descendants; leaves are skipped.
    public let wrapperCount: Int

    /// Capture exact identities and metadata eligibility once for either one or multiple rows.
    /// Full inherited XML-context/namespace preflight remains off-main in the document command.
    public init(snapshot: EditorSnapshot, componentIDs: [String]? = nil) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        let requested = componentIDs ?? Array(snapshot.selectedComponentIDs)
        let components = snapshot.componentTree.rows.map(\.component)
        guard let plan = try? ComponentUngroupPlan(components: components, ids: requested), !plan.wrapperIDs.isEmpty
        else {
            ids = []
            wrapperCount = 0
            return
        }
        let keys = Set(requested.map { Data($0.utf8) })
        ids = components.filter { keys.contains(Data($0.id.utf8)) }.map(\.id)
        wrapperCount = plan.wrapperIDs.count
    }
    /// Whether the exact captured document/revision/selection/constraint intent is still current.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        wrapperCount > 0 && context.isCurrent(in: snapshot)
    }
}

public enum ComponentUngroupSelectionError: Error, Equatable, Sendable { case staleTarget }

extension EditorState {
    /// Ungroup all explicit eligible wrappers in one cancellable Undo transaction.
    /// - Throws: Stale target or original document/context errors, without partial publication.
    public mutating func ungroupComponents(target: ComponentUngroupTarget) throws {
        try Task.checkCancellation()
        guard target.isCurrent(in: snapshot) else { throw ComponentUngroupSelectionError.staleTarget }
        var next = self
        try next.apply([.ungroupComponents(ids: target.ids)])
        try Task.checkCancellation()
        self = next
    }
}
