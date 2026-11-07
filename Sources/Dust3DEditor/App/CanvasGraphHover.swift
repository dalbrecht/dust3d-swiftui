import Dust3DEditorModel
import Foundation

/// A hover identifies graph content independent of the profile displaying it.
enum CanvasGraphHover: Equatable {
    case node(String)
    case edge(String)

    static func hit(at point: CanvasPoint, projection: CanvasProjection, snapshot: EditorSnapshot) -> Self? {
        if let node = snapshot.nodes.last(where: {
            guard $0.isVisible else { return false }
            let center = projection.point(for: $0.value.position)
            return hypot(center.x - point.x, center.y - point.y) <= 18
        }) {
            return .node(node.id)
        }
        return projection.edgeID(near: point, nodes: snapshot.nodes, edges: snapshot.edges).map(Self.edge)
    }
}
