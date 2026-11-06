import Dust3DDocument
import Foundation

/// Immutable interaction identity; constructing this value never extracts or copies PNG payloads.
public struct ReferenceColorTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    /// Capture the originating document, revision, explicit selection and constraints before any await.
    public init(snapshot: EditorSnapshot) { context = CanvasAdjustmentTarget(snapshot: snapshot) }
    /// Test scalar epochs only; exact returned source bytes are validated on the editing actor.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { context.isCurrent(in: snapshot) }
}

/// One atomic Auto Color result, retaining the original skip causes without presenting a partial edit.
public struct ReferenceColorReceipt: Sendable {
    public let snapshot: EditorSnapshot
    public let changedComponentCount: Int
    public let skippedReadOnlyObjects: Int
    public let skippedOutsideObjects: Int
    public let didChange: Bool

    init(snapshot: EditorSnapshot, plan: GraphReferenceColorPlan, previous: EditorSnapshot) {
        self.snapshot = snapshot
        let before = Dictionary(uniqueKeysWithValues: previous.componentTree.rows.map { ($0.id, $0.component.color) })
        let after = Dictionary(uniqueKeysWithValues: snapshot.componentTree.rows.map { ($0.id, $0.component.color) })
        changedComponentCount = plan.updates.filter { before[$0.componentID] != after[$0.componentID] }.count
        skippedReadOnlyObjects = plan.skippedReadOnlyObjects
        skippedOutsideObjects = plan.skippedOutsideObjects
        didChange = snapshot.documentRevision != previous.documentRevision
    }
}

extension EditorState {
    /// Remove explicit part color overrides represented by selected nodes; no image decoding is needed.
    /// - Parameter target: Optional captured selection/document/constraint identity.
    /// - Returns: The complete plan, including read-only skips.
    /// - Throws: Stale or ownership errors before any mutation; all changes share one undo transaction.
    @discardableResult
    public mutating func clearSelectedPartColors(target: CanvasAdjustmentTarget? = nil) throws
        -> GraphReferenceColorPlan
    {
        let current = snapshot
        if let target, !target.isCurrent(in: current) { throw EditorError.staleReferenceColor }
        guard !current.selectedIDs.isEmpty else { throw EditorError.invalidReferenceColorSelection }
        let plan = try GraphReferenceColorPlan.clear(snapshot: current)
        try commitReferenceColorPlan(plan)
        return plan
    }

    /// Sample and atomically apply part colors. Call through EditorSession off the UI actor.
    /// - Parameters: `referencePNG` is the service's owned source; equality/extraction occurs here, not in UI admission.
    ///   `raster` and `layout` are paired with the actually displayed fitted image; `target` captures interaction epochs.
    /// - Returns: The full validated plan and skip counts.
    /// - Throws: Stale source/context or ownership errors before any mutation.
    public mutating func autoColorSelectedParts(
        raster: ReferenceColorRaster, layout: ReferenceColorSamplingLayout,
        referencePNG: Data, target: ReferenceColorTarget
    ) throws -> GraphReferenceColorPlan {
        let current = snapshot
        guard target.isCurrent(in: current) else { throw EditorError.staleReferenceColor }
        guard !current.selectedIDs.isEmpty else { throw EditorError.invalidReferenceColorSelection }
        guard current.document.referenceImagePNG == referencePNG else {
            throw EditorError.staleReferenceColor
        }
        try Task.checkCancellation()
        let plan = try GraphReferenceColorPlan.autoColor(snapshot: current, raster: raster, layout: layout)
        try Task.checkCancellation()
        try commitReferenceColorPlan(plan)
        return plan
    }

    private mutating func commitReferenceColorPlan(_ plan: GraphReferenceColorPlan) throws {
        try Task.checkCancellation()
        var next = self
        try next.apply(plan.commands)
        try Task.checkCancellation()
        self = next
    }
}
