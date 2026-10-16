import Dust3DDocument
import Foundation

/// Immutable origin gesture baseline. Previewing never mutates a document or its history.
public struct OriginDrag: Sendable {
    private let documentIdentity: UUID
    private let revision: Int
    private let constraintRevision: Int
    private let locks: Set<EditingConstraint>
    private let origin: NodePosition
    private let projection: CanvasProjection

    /// Capture a supported origin and fixed projection; throws `EditorError.unavailableOrigin` otherwise.
    public init(snapshot: EditorSnapshot, projection: CanvasProjection) throws {
        guard let origin = snapshot.origin else { throw EditorError.unavailableOrigin }
        documentIdentity = snapshot.documentIdentity
        revision = snapshot.documentRevision
        constraintRevision = snapshot.constraintRevision
        locks = snapshot.locks
        self.origin = origin
        self.projection = projection
    }

    /// Project total displacement with axis locks; radius and per-part restrictions do not constrain origin.
    /// The command boundary validates finite coordinates and document limits before committing.
    public func position(by translation: CanvasPoint) -> NodePosition {
        projection.moving(origin, by: translation, locks: locks)
    }

    /// Replacements, intervening document commands and changed constraints invalidate a gesture.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && revision == snapshot.documentRevision
            && constraintRevision == snapshot.constraintRevision && locks == snapshot.locks
    }
}
