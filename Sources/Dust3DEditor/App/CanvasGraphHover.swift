import Dust3DDocument
import Dust3DEditorModel
import Foundation

/// A hover identifies graph content independent of the profile displaying it.
enum CanvasGraphHover: Equatable {
    case node(String)
    case edge(String)

    var partTarget: PartGraphTarget {
        switch self {
        case .node(let id): .node(id)
        case .edge(let id): .edge(id)
        }
    }

    struct Cache {
        final class Entry {
            private let documentID: UUID
            private let revision: Int
            private let projection: CanvasProjection
            private let rigEdgesOnly: Bool
            private let nodes: [(id: String, point: CanvasPoint)]
            private let positions: [String: CanvasPoint]
            private let edges: [DocumentEdge]

            init(snapshot: EditorSnapshot, projection: CanvasProjection, rigEdgesOnly: Bool) {
                documentID = snapshot.documentIdentity
                revision = snapshot.documentRevision
                self.projection = projection
                self.rigEdgesOnly = rigEdgesOnly
                nodes = snapshot.nodes.filter(\.isVisible).map {
                    ($0.id, projection.point(for: $0.value.position))
                }
                positions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.point) })
                if rigEdgesOnly {
                    let editable = EdgeBoneAssignmentEligibility.edgeIDs(
                        nodes: snapshot.nodes, edges: snapshot.edges, parts: snapshot.parts)
                    edges = snapshot.edges.filter { editable.contains(Data($0.id.utf8)) }
                } else {
                    edges = snapshot.edges
                }
            }

            func matches(snapshot: EditorSnapshot, projection: CanvasProjection, rigEdgesOnly: Bool) -> Bool {
                documentID == snapshot.documentIdentity && revision == snapshot.documentRevision
                    && self.projection == projection && self.rigEdgesOnly == rigEdgesOnly
            }

            func hit(at point: CanvasPoint) -> CanvasGraphHover? {
                if !rigEdgesOnly,
                    let node = nodes.last(where: { hypot($0.point.x - point.x, $0.point.y - point.y) <= 18 })
                {
                    return .node(node.id)
                }
                return CanvasProjection.edgeID(near: point, positions: positions, edges: edges).map(
                    CanvasGraphHover.edge)
            }
        }

        private(set) var entry: Entry?

        mutating func hit(
            at point: CanvasPoint, projection: CanvasProjection, snapshot: EditorSnapshot, rigEdgesOnly: Bool = false
        ) -> CanvasGraphHover? {
            if let entry, entry.matches(snapshot: snapshot, projection: projection, rigEdgesOnly: rigEdgesOnly) {
                return entry.hit(at: point)
            }
            let entry = Entry(snapshot: snapshot, projection: projection, rigEdgesOnly: rigEdgesOnly)
            self.entry = entry
            return entry.hit(at: point)
        }
    }
}
