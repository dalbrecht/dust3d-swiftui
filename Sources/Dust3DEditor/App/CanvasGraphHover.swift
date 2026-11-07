import Dust3DDocument
import Dust3DEditorModel
import Foundation

/// A hover identifies graph content independent of the profile displaying it.
enum CanvasGraphHover: Equatable {
    case node(String)
    case edge(String)

    struct Cache {
        final class Entry {
            private let documentID: UUID
            private let revision: Int
            private let projection: CanvasProjection
            private let nodes: [(id: String, point: CanvasPoint)]
            private let positions: [String: CanvasPoint]
            private let edges: [DocumentEdge]

            init(snapshot: EditorSnapshot, projection: CanvasProjection) {
                documentID = snapshot.documentIdentity
                revision = snapshot.documentRevision
                self.projection = projection
                nodes = snapshot.nodes.filter(\.isVisible).map {
                    ($0.id, projection.point(for: $0.value.position))
                }
                positions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.point) })
                edges = snapshot.edges
            }

            func matches(snapshot: EditorSnapshot, projection: CanvasProjection) -> Bool {
                documentID == snapshot.documentIdentity && revision == snapshot.documentRevision
                    && self.projection == projection
            }

            func hit(at point: CanvasPoint) -> CanvasGraphHover? {
                if let node = nodes.last(where: { hypot($0.point.x - point.x, $0.point.y - point.y) <= 18 }) {
                    return .node(node.id)
                }
                return CanvasProjection.edgeID(near: point, positions: positions, edges: edges).map(
                    CanvasGraphHover.edge)
            }
        }

        private(set) var entry: Entry?

        mutating func hit(at point: CanvasPoint, projection: CanvasProjection, snapshot: EditorSnapshot)
            -> CanvasGraphHover?
        {
            if let entry, entry.matches(snapshot: snapshot, projection: projection) {
                return entry.hit(at: point)
            }
            let entry = Entry(snapshot: snapshot, projection: projection)
            self.entry = entry
            return entry.hit(at: point)
        }
    }
}
