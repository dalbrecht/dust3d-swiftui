import Foundation

/// Captures a document epoch before collecting new stored-animation intent.
/// It has no selected-row dependency and retains no archive or native owner.
public struct AnimationCreationTarget: Sendable {
    private let documentIdentity: UUID
    private let documentRevision: Int

    /// Capture a source-correlated animation observation, including a successfully empty list.
    /// - Parameter snapshot: Accepted document/list from the editor's serial actor.
    /// - Throws: Original optional metadata cause, without changing the document.
    /// - Example: `let target = try AnimationCreationTarget(snapshot: observation)`.
    public init(snapshot: EditorAnimationSnapshot) throws {
        if let cause = snapshot.list.issue { throw cause }
        documentIdentity = snapshot.editor.documentIdentity
        documentRevision = snapshot.editor.documentRevision
    }

    /// Compare semantic source epochs; selection and interaction locks do not retire a draft.
    /// - Parameter snapshot: Current accepted editor state.
    /// - Returns: False after an edit, Undo/Redo or successful replacement Open.
    /// - Example: `target.isCurrent(in: currentSnapshot)`.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && documentRevision == snapshot.documentRevision
    }
}
