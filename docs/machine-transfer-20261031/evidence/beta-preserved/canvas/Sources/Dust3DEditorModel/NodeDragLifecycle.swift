import Dust3DDocument

/// Orders transient canvas callbacks without relying on reset and completion callback ordering.
public struct NodeDragLifecycle: Sendable {
    /// Current baseline and displacement while a gesture is active.
    public struct Preview: Sendable {
        public let baseline: NodeDrag
        public let translation: CanvasPoint
    }

    private var retained: Preview?
    private var canBegin = true
    private var invalidated = false
    /// Only an active, valid gesture is displayed.
    public var preview: Preview? { canBegin || invalidated ? nil : retained }
    /// Identity of the node whose gesture remains eligible for completion.
    public var anchorID: String? { retained?.baseline.anchorID }

    public init() {}

    /// Capture a baseline at the first update and retain it for the entire gesture.
    /// - Throws: The original anchor validation error.
    public mutating func update(
        anchorID: String, snapshot: EditorSnapshot, projection: CanvasProjection, translation: CanvasPoint
    ) throws {
        if canBegin {
            retained = Preview(
                baseline: try NodeDrag(anchorID: anchorID, snapshot: snapshot, projection: projection),
                translation: translation)
            invalidated = false
            canBegin = false
            return
        }
        guard !invalidated, let current = retained else { return }
        guard current.baseline.anchorID == anchorID, current.baseline.isCurrent(in: snapshot) else {
            invalidate()
            return
        }
        retained = Preview(baseline: current.baseline, translation: translation)
    }

    /// Suppress preview and reject completion while the current gesture remains active.
    public mutating func invalidate() { invalidated = true }

    /// Hide a completed or cancelled preview while retaining the baseline for a later completion callback.
    public mutating func gestureBecameInactive() { canBegin = true }

    /// Consume a valid baseline regardless of whether the inactive callback arrived first.
    public mutating func finish() -> NodeDrag? {
        let result = invalidated ? nil : retained?.baseline
        retained = nil
        invalidated = false
        canBegin = true
        return result
    }
}
