import Foundation

/// A queued canvas input belongs to one immutable document, selection and interaction-constraint epoch.
public struct CanvasAdjustmentTarget: Sendable {
    private let documentIdentity: UUID
    private let documentRevision: Int
    private let selectionRevision: Int
    private let constraintRevision: Int

    /// Capture a menu, keyboard or wheel target before dispatching its already-converted delta/factor.
    /// - Parameter snapshot: The originating window snapshot; actual canvas height is captured by the UI.
    public init(snapshot: EditorSnapshot) {
        documentIdentity = snapshot.documentIdentity
        documentRevision = snapshot.documentRevision
        selectionRevision = snapshot.selectionRevision
        constraintRevision = snapshot.constraintRevision
    }

    /// Whether the originating window, archive, explicit selection and constraints still match.
    /// - Parameter snapshot: The latest model snapshot.
    /// - Returns: False even when a selection or lock changed and then returned to its original value.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && documentRevision == snapshot.documentRevision
            && selectionRevision == snapshot.selectionRevision && constraintRevision == snapshot.constraintRevision
    }
}
