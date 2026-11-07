import Dust3DDocument
import Dust3DEditorModel
import Foundation

/// Model-coordinate preview shared by the editing and companion profiles.
struct CanvasProfileMotion {
    enum Payload {
        case ordinary(NodeDragLifecycle.Preview)
        case shifted([String: NodePosition])
    }

    let lease: UUID
    let token: UUID
    private let target: CanvasAdjustmentTarget
    private var payload: Payload?

    init(snapshot: EditorSnapshot, lease: UUID, token: UUID) {
        self.lease = lease
        self.token = token
        target = CanvasAdjustmentTarget(snapshot: snapshot)
    }

    func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        target.isCurrent(in: snapshot)
    }

    mutating func update(_ payload: Payload, lease: UUID, token: UUID, snapshot: EditorSnapshot) -> Bool {
        guard self.lease == lease, self.token == token, isCurrent(in: snapshot) else { return false }
        self.payload = payload
        return true
    }

    func position(of node: DocumentNode, in snapshot: EditorSnapshot) -> NodePosition {
        guard isCurrent(in: snapshot) else { return node.value.position }
        switch payload {
        case .shifted(let positions):
            return positions[node.id] ?? node.value.position
        case .ordinary(let preview):
            guard node.isEditable, preview.baseline.includes(node.id), preview.baseline.isCurrent(in: snapshot) else {
                return node.value.position
            }
            return preview.baseline.position(of: node.value.position, by: preview.translation)
        case nil:
            return node.value.position
        }
    }
}
