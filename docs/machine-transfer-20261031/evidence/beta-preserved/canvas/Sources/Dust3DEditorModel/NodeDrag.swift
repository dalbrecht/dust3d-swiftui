import Dust3DDocument
import Foundation

/// Immutable node gesture baseline, captured before a canvas drag changes presentation.
public struct NodeDrag: Sendable {
    private let documentIdentity: UUID
    private let revision: Int
    private let constraintRevision: Int
    private let selectedIDs: Set<String>
    private let selectedEdgeID: String?
    private let selectedPartID: String?
    private let selectedComponentIDs: Set<String>
    private let locks: Set<EditingConstraint>
    private let projection: CanvasProjection
    private let origin: NodePosition
    /// The editable node that anchors the gesture.
    public let anchorID: String

    /// Capture the anchor, selection, locks and projection for an atomic canvas gesture.
    /// - Throws: `DocumentError.missingNode` or `EditorError.readOnlyNode` for an invalid anchor.
    public init(anchorID: String, snapshot: EditorSnapshot, projection: CanvasProjection) throws {
        guard let node = snapshot.nodes.first(where: { $0.id == anchorID }) else {
            throw DocumentError.missingNode(anchorID)
        }
        guard node.isEditable else { throw EditorError.readOnlyNode }
        self.anchorID = anchorID
        documentIdentity = snapshot.documentIdentity
        revision = snapshot.documentRevision
        constraintRevision = snapshot.constraintRevision
        selectedIDs = snapshot.selectedIDs
        selectedEdgeID = snapshot.selectedEdgeID
        selectedPartID = snapshot.selectedPartID
        selectedComponentIDs = snapshot.selectedComponentIDs
        locks = snapshot.locks
        self.projection = projection
        origin = node.value.position
    }

    /// Position of the anchor after a total screen-point displacement.
    public func position(by translation: CanvasPoint) -> NodePosition {
        projection.moving(origin, by: translation, locks: locks)
    }

    /// Project a participating node with the captured geometry and locks.
    public func position(of node: NodePosition, by translation: CanvasPoint) -> NodePosition {
        projection.moving(node, by: translation, locks: locks)
    }

    /// Nodes that participate in this captured selection.
    public func includes(_ id: String) -> Bool {
        selectedIDs.contains(anchorID) ? selectedIDs.contains(id) : id == anchorID
    }

    /// Whether this gesture still targets the same document, selection and constraints.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && revision == snapshot.documentRevision
            && constraintRevision == snapshot.constraintRevision && locks == snapshot.locks
            && selectedIDs == snapshot.selectedIDs && selectedEdgeID == snapshot.selectedEdgeID
            && selectedPartID == snapshot.selectedPartID && selectedComponentIDs == snapshot.selectedComponentIDs
    }
}
