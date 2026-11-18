import Dust3DDocument
import Foundation

/// A bounded, canvas-local freehand path. Polygon interiors use the odd-even rule.
package struct CanvasLasso: Sendable {
    package static let maximumPointCount = 512
    package private(set) var points: [CanvasPoint] = []
    package private(set) var bounds: CanvasSelectionRectangle?

    package init() {}

    package mutating func append(_ point: CanvasPoint) {
        guard [point.x, point.y].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { return }
        if let previous = points.last, hypot(point.x - previous.x, point.y - previous.y) < 2 { return }
        // Keep sampling a long gesture while preserving its overall path and original start.
        if points.count == Self.maximumPointCount {
            points = stride(from: 0, to: points.count, by: 2).map { points[$0] }
        }
        points.append(point)
        if let bounds {
            self.bounds = .init(
                from: .init(x: min(point.x, bounds.minimum.x), y: min(point.y, bounds.minimum.y)),
                to: .init(x: max(point.x, bounds.maximum.x), y: max(point.y, bounds.maximum.y)))
        } else {
            bounds = .init(from: point, to: point)
        }
    }

    package func contains(_ point: CanvasPoint) -> Bool {
        guard let bounds, point.x >= bounds.minimum.x, point.x <= bounds.maximum.x,
            point.y >= bounds.minimum.y, point.y <= bounds.maximum.y
        else { return false }
        guard points.count >= 3 else { return true }

        var inside = false
        var previous = points[points.count - 1]
        for vertex in points {
            let x = vertex.x - previous.x
            let y = vertex.y - previous.y
            let dx = point.x - previous.x
            let dy = point.y - previous.y
            if dx * y == dy * x,
                point.x >= min(previous.x, vertex.x), point.x <= max(previous.x, vertex.x),
                point.y >= min(previous.y, vertex.y), point.y <= max(previous.y, vertex.y)
            {
                return true
            }
            if (previous.y > point.y) != (vertex.y > point.y),
                point.x < previous.x + dy * x / y
            {
                inside.toggle()
            }
            previous = vertex
        }
        return inside
    }

    /// Intersect a butt-capped edge stroke, or a disk for a collapsed projection.
    package func intersectsStroke(from: CanvasPoint, to: CanvasPoint, halfWidth: Double) -> Bool {
        guard let bounds, [from.x, from.y, to.x, to.y, halfWidth].allSatisfy(\.isFinite), halfWidth >= 0,
            min(from.x, to.x) - halfWidth <= bounds.maximum.x, max(from.x, to.x) + halfWidth >= bounds.minimum.x,
            min(from.y, to.y) - halfWidth <= bounds.maximum.y, max(from.y, to.y) + halfWidth >= bounds.minimum.y
        else { return false }
        if contains(from) || contains(to) { return true }

        let vertices = selectionVertices(in: bounds)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length.isFinite else { return false }
        if length == 0 {
            return boundaryDistance(from: from, vertices: vertices) <= halfWidth
        }

        let tangentX = dx / length
        let tangentY = dy / length
        func local(_ point: CanvasPoint) -> CanvasPoint {
            let x = point.x - from.x
            let y = point.y - from.y
            return .init(x: x * tangentX + y * tangentY, y: y * tangentX - x * tangentY)
        }
        var previous = local(vertices[vertices.count - 1])
        for vertex in vertices {
            let end = local(vertex)
            var enter = 0.0
            var exit = 1.0
            if Self.clip(previous.x, end.x, to: 0...length, enter: &enter, exit: &exit),
                Self.clip(previous.y, end.y, to: -halfWidth...halfWidth, enter: &enter, exit: &exit)
            {
                return true
            }
            previous = end
        }
        return false
    }

    fileprivate func intersectsNodeCircle(center: CanvasPoint, radius: Double) -> Bool {
        guard let bounds, [center.x, center.y, radius].allSatisfy(\.isFinite), radius > 0,
            center.x - radius < bounds.maximum.x, center.x + radius > bounds.minimum.x,
            center.y - radius < bounds.maximum.y, center.y + radius > bounds.minimum.y
        else { return false }
        return contains(center) || boundaryDistance(from: center, vertices: selectionVertices(in: bounds)) < radius
    }

    private func selectionVertices(in bounds: CanvasSelectionRectangle) -> [CanvasPoint] {
        if points.count >= 3 { return points }
        return [
            bounds.minimum, .init(x: bounds.maximum.x, y: bounds.minimum.y),
            bounds.maximum, .init(x: bounds.minimum.x, y: bounds.maximum.y),
        ]
    }

    private func boundaryDistance(from point: CanvasPoint, vertices: [CanvasPoint]) -> Double {
        var nearest = Double.infinity
        var previous = vertices[vertices.count - 1]
        for vertex in vertices {
            let segmentX = vertex.x - previous.x
            let segmentY = vertex.y - previous.y
            let lengthSquared = segmentX * segmentX + segmentY * segmentY
            let x = point.x - previous.x
            let y = point.y - previous.y
            let t = lengthSquared == 0 ? 0 : min(1, max(0, (x * segmentX + y * segmentY) / lengthSquared))
            nearest = min(nearest, hypot(x - t * segmentX, y - t * segmentY))
            previous = vertex
        }
        return nearest
    }

    private static func clip(
        _ start: Double, _ end: Double, to range: ClosedRange<Double>, enter: inout Double, exit: inout Double
    ) -> Bool {
        let delta = end - start
        if delta == 0 { return range.contains(start) }
        let a = (range.lowerBound - start) / delta
        let b = (range.upperBound - start) / delta
        enter = max(enter, min(a, b))
        exit = min(exit, max(a, b))
        return enter <= exit
    }
}

extension CanvasProjection {
    package func nodeIDs(in lasso: CanvasLasso, nodes: [DocumentNode]) -> Set<String> {
        guard let bounds = lasso.bounds else { return [] }
        if lasso.points.count < 3 { return nodeIDs(in: bounds, nodes: nodes) }
        return Set(
            nodes.lazy.filter { node in
                guard !Task.isCancelled, node.isVisible else { return false }
                let center = point(for: node.value.position)
                return lasso.intersectsNodeCircle(center: center, radius: nodeSelectionRadius(node))
            }.map(\.id))
    }

    package func edgeIDs(
        in lasso: CanvasLasso, nodes: [DocumentNode], edges: [DocumentEdge], selectedEdgeIDs: Set<String> = []
    ) -> Set<String> {
        if lasso.points.count < 3, let bounds = lasso.bounds {
            return edgeIDs(in: bounds, nodes: nodes, edges: edges, selectedEdgeIDs: selectedEdgeIDs)
        }
        let positions = Dictionary(
            uniqueKeysWithValues: nodes.lazy.filter(\.isVisible).map { ($0.id, point(for: $0.value.position)) })
        return Set(
            edges.lazy.filter { edge in
                guard !Task.isCancelled, let from = positions[edge.fromID], let to = positions[edge.toID] else {
                    return false
                }
                return lasso.intersectsStroke(from: from, to: to, halfWidth: selectedEdgeIDs.contains(edge.id) ? 2 : 1)
            }.map(\.id))
    }
}
