import Dust3DDocument
import Foundation

/// Immutable node gesture baseline. Previewing does not mutate document bytes or history.
public struct NodeDrag: Sendable {
    /// Node whose displacement determines the selection's movement.
    public let anchorID: String
    private let documentIdentity: UUID
    private let revision: Int
    private let constraintRevision: Int
    private let locks: Set<EditingConstraint>
    private let selectedIDs: Set<String>
    private let selectedEdgeID: String?
    private let position: NodePosition
    private let projection: CanvasProjection

    /// Capture an editable anchor and fixed projection.
    /// - Throws: `DocumentError.invalidNode` for a missing anchor or `EditorError.readOnlyNode` for a protected one.
    public init(snapshot: EditorSnapshot, anchorID: String, projection: CanvasProjection) throws {
        guard let node = snapshot.nodes.first(where: { $0.id == anchorID }) else { throw DocumentError.invalidNode }
        guard node.isEditable else { throw EditorError.readOnlyNode }
        self.anchorID = anchorID
        documentIdentity = snapshot.documentIdentity
        revision = snapshot.documentRevision
        constraintRevision = snapshot.constraintRevision
        locks = snapshot.locks
        selectedIDs = snapshot.selectedIDs
        selectedEdgeID = snapshot.selectedEdgeID
        position = node.value.position
        self.projection = projection
    }

    /// Project total screen displacement using the captured axis locks.
    /// The command boundary validates finite values before writing.
    public func position(by translation: CanvasPoint) -> NodePosition {
        projection.moving(position, by: translation, locks: locks)
    }

    /// Preview participating editable nodes using the captured selection and projection.
    /// - Returns: The original position for nodes outside the gesture's editable group.
    public func previewPosition(for node: DocumentNode, by translation: CanvasPoint) -> NodePosition {
        let participates = selectedIDs.contains(anchorID) ? selectedIDs.contains(node.id) : node.id == anchorID
        guard participates, node.isEditable else { return node.value.position }
        return projection.moving(node.value.position, by: translation, locks: locks)
    }

    /// Reject replacements, edits, constraint changes and selection changes before committing.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && revision == snapshot.documentRevision
            && constraintRevision == snapshot.constraintRevision && locks == snapshot.locks
            && selectedIDs == snapshot.selectedIDs && selectedEdgeID == snapshot.selectedEdgeID
    }
}
