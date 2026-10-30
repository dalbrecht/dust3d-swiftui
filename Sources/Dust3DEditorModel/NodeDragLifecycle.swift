import Dust3DDocument
import Foundation

/// Coordinates transient node gestures by their pointer activation identity.
public struct NodeDragLifecycle: Sendable {
    /// Current baseline and displacement while a gesture is active.
    public struct Preview: Sendable {
        public let baseline: NodeDrag
        public let translation: CanvasPoint
    }

    private var token: UUID?
    private var retained: Preview?
    private var invalidated = false
    /// Only an active, valid gesture is displayed.
    public var preview: Preview? { invalidated ? nil : retained }

    public init() {}

    /// Keep canvas rendering in the gesture's coordinate system until it ends.
    public func displayProjection(fallback: CanvasProjection) -> CanvasProjection {
        preview?.baseline.projection ?? fallback
    }

    /// Capture a new pointer activation, replacing any previous gesture.
    /// - Throws: The original anchor validation error.
    public mutating func begin(token: UUID, anchorID: String, snapshot: EditorSnapshot, projection: CanvasProjection)
        throws
    {
        self.token = nil
        retained = nil
        invalidated = false
        let baseline = try NodeDrag(anchorID: anchorID, snapshot: snapshot, projection: projection)
        self.token = token
        retained = Preview(baseline: baseline, translation: .init(x: 0, y: 0))
    }

    /// Update only the activation that created the current baseline.
    public mutating func update(token: UUID, snapshot: EditorSnapshot, translation: CanvasPoint) {
        guard self.token == token, !invalidated, let current = retained else { return }
        guard current.baseline.isCurrent(in: snapshot) else {
            invalidate()
            return
        }
        retained = Preview(baseline: current.baseline, translation: translation)
    }

    /// Suppress preview and reject completion of the current gesture.
    public mutating func invalidate() { invalidated = true }

    /// Cancel only the activation that owns the current baseline.
    public mutating func cancel(token: UUID) {
        guard self.token == token else { return }
        self.token = nil
        retained = nil
        invalidated = false
    }

    /// Consume a valid baseline only for the matching pointer activation.
    public mutating func finish(token: UUID) -> NodeDrag? {
        guard self.token == token else { return nil }
        let result = invalidated ? nil : retained?.baseline
        cancel(token: token)
        return result
    }
}
