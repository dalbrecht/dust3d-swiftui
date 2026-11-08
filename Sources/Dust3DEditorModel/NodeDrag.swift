import Dust3DDocument
import Foundation

/// Immutable node gesture baseline, captured before a canvas drag changes presentation.
public struct NodeDrag: Sendable {
    private let documentIdentity: UUID
    private let revision: Int
    private let constraintRevision: Int
    private let selectionRevision: Int
    private let selectedIDs: Set<String>
    private let selectedEdgeIDs: Set<String>
    private let participants: Set<String>
    private let selectedPartID: String?
    private let selectedComponentIDs: Set<String>
    private let locks: Set<EditingConstraint>
    /// The fixed coordinate system captured when the gesture began.
    public let projection: CanvasProjection
    private let origin: NodePosition
    /// The editable node that anchors the gesture.
    public let anchorID: String
    package let edgeID: String?

    /// Capture the anchor, selection, locks and projection for an atomic canvas gesture.
    /// - Throws: `DocumentError.missingNode` or `EditorError.readOnlyNode` for an invalid anchor.
    public init(anchorID: String, snapshot: EditorSnapshot, projection: CanvasProjection) throws {
        guard let node = snapshot.nodes.first(where: { $0.id == anchorID }) else {
            throw DocumentError.missingNode(anchorID)
        }
        guard node.isEditable else { throw EditorError.readOnlyNode }
        let selected = snapshot.transformNodeIDs
        self.init(
            anchor: node, edgeID: nil, participants: selected.contains(anchorID) ? selected : [anchorID],
            snapshot: snapshot, projection: projection)
    }

    /// Resolve the same visible stroke as an ordinary edge tap; an ineligible hit does not fall through.
    package static func edgeStroke(at point: CanvasPoint, snapshot: EditorSnapshot, projection: CanvasProjection)
        -> Self?
    {
        guard let id = projection.edgeID(near: point, nodes: snapshot.nodes, edges: snapshot.edges),
            let edge = snapshot.edges.first(where: { $0.id == id }),
            let anchor = snapshot.nodes.first(where: { $0.id == edge.fromID && $0.isEditable }),
            snapshot.nodes.contains(where: { $0.id == edge.toID && $0.isEditable })
        else { return nil }
        let participants = snapshot.selectedEdgeIDs.contains(id) ? snapshot.transformNodeIDs : [edge.fromID, edge.toID]
        return Self(anchor: anchor, edgeID: id, participants: participants, snapshot: snapshot, projection: projection)
    }

    private init(
        anchor: DocumentNode, edgeID: String?, participants: Set<String>, snapshot: EditorSnapshot,
        projection: CanvasProjection
    ) {
        anchorID = anchor.id
        self.edgeID = edgeID
        documentIdentity = snapshot.documentIdentity
        revision = snapshot.documentRevision
        constraintRevision = snapshot.constraintRevision
        selectionRevision = snapshot.selectionRevision
        selectedIDs = snapshot.selectedIDs
        selectedEdgeIDs = snapshot.selectedEdgeIDs
        self.participants = participants
        selectedPartID = snapshot.selectedPartID
        selectedComponentIDs = snapshot.selectedComponentIDs
        locks = snapshot.locks
        self.projection = projection
        origin = anchor.value.position
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
        participants.contains(id)
    }

    /// Whether this gesture still targets the same document, selection and constraints.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && revision == snapshot.documentRevision
            && constraintRevision == snapshot.constraintRevision && selectionRevision == snapshot.selectionRevision
            && locks == snapshot.locks
            && selectedIDs == snapshot.selectedIDs && selectedEdgeIDs == snapshot.selectedEdgeIDs
            && selectedPartID == snapshot.selectedPartID && selectedComponentIDs == snapshot.selectedComponentIDs
    }
}
