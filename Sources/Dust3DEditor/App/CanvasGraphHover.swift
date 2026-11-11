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

    /// Rank hits on the tapered edge by midpoint distance, as Qt does for overlapping items.
    static func taperedEdge(
        at point: CanvasPoint, edges: [DocumentEdge], position: (String) -> CanvasPoint?, closerThan limit: Double
    ) -> String? {
        var closest: String?
        var distance = limit
        for edge in edges {
            guard let from = position(edge.fromID), let to = position(edge.toID) else { continue }
            let dx = to.x - from.x
            let dy = to.y - from.y
            let length = hypot(dx, dy)
            guard length > 0, length.isFinite else { continue }
            let x = point.x - from.x
            let y = point.y - from.y
            let ux = dx / length
            let uy = dy / length
            let along = x * ux + y * uy
            guard along >= 0, along <= length,
                abs(x * uy - y * ux) <= 2 * (1 - along / length)
            else { continue }
            let midpointDistance = hypot(x - dx / 2, y - dy / 2)
            if midpointDistance < distance {
                closest = edge.id
                distance = midpointDistance
            }
        }
        return closest
    }

    struct Cache {
        final class Entry {
            private let documentID: UUID
            private let revision: Int
            private let projection: CanvasProjection
            private let rigEdgesOnly: Bool
            private let nodes: [(id: String, point: CanvasPoint, radius: Double)]
            private let positions: [String: CanvasPoint]
            private let edges: [DocumentEdge]

            init(snapshot: EditorSnapshot, projection: CanvasProjection, rigEdgesOnly: Bool) {
                documentID = snapshot.documentIdentity
                revision = snapshot.documentRevision
                self.projection = projection
                self.rigEdgesOnly = rigEdgesOnly
                nodes = snapshot.nodes.filter(\.isVisible).map {
                    let radius = CanvasNodeMarkerGeometry.hitRadius(
                        projectedDiameter: $0.value.radius * projection.scale * 2)
                    return ($0.id, projection.point(for: $0.value.position), radius)
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
                if !rigEdgesOnly {
                    var nearestID: String?
                    var nearestDistance = Double.infinity
                    for node in nodes {
                        let distance = hypot(node.point.x - point.x, node.point.y - point.y)
                        if distance <= node.radius, distance <= nearestDistance {
                            nearestID = node.id
                            nearestDistance = distance
                        }
                    }
                    if let nearestID {
                        if let edge = CanvasGraphHover.taperedEdge(
                            at: point, edges: edges, position: { positions[$0] }, closerThan: nearestDistance)
                        {
                            return .edge(edge)
                        }
                        return .node(nearestID)
                    }
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
