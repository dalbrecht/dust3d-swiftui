import Foundation

/// Document epoch captured by a stored-animation creation form, including a valid empty catalog.
public struct AnimationCreationTarget: Sendable {
    private let documentIdentity: UUID
    private let documentRevision: Int

    /// Capture a successfully read catalog without requiring any selected row.
    /// - Parameter snapshot: One accepted actor observation of document and optional catalog.
    /// - Throws: Original catalog error before a target is created.
    /// - Example: `try AnimationCreationTarget(snapshot: value)`.
    public init(snapshot: EditorAnimationSnapshot) throws {
        if let cause = snapshot.list.issue { throw cause }
        documentIdentity = snapshot.editor.documentIdentity
        documentRevision = snapshot.editor.documentRevision
    }

    /// Check the accepted source; Open and every semantic edit/Undo/Redo retire this target.
    /// - Parameter snapshot: Current accepted state, rather than a retained preview after failed Open.
    /// - Returns: True only for the captured document UUID and revision.
    /// - Example: `target.isCurrent(in: current)`.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && documentRevision == snapshot.documentRevision
    }
}
