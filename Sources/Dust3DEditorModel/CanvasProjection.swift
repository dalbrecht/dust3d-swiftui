import Dust3DDocument
import Foundation

public enum EditingPlane: String, CaseIterable, Sendable {
    case front = "Front (X/Y)"
    case side = "Side (Z/Y)"
}

public struct CanvasPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Direction-independent marquee bounds in canvas points. Invalid input selects nothing.
public struct CanvasSelectionRectangle: Sendable {
    public let minimum: CanvasPoint
    public let maximum: CanvasPoint
    public let isValid: Bool

    public init(from start: CanvasPoint, to end: CanvasPoint) {
        isValid = [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite)
        minimum = .init(x: min(start.x, end.x), y: min(start.y, end.y))
        maximum = .init(x: max(start.x, end.x), y: max(start.y, end.y))
    }
}

/// Fit bounds are held stable during an edit so dragging cannot move its own coordinate system.
public struct CanvasBounds: Sendable {
    let minimum: NodePosition
    let maximum: NodePosition

    /// Fit visible nodes, an optional reference rectangle and a complete supported origin.
    /// Invalid origins are ignored; callers can preserve unsupported source metadata separately.
    public init(nodes: [DocumentNode], referenceImageAspectRatio: Double? = nil, origin: NodePosition? = nil) {
        let visible = nodes.filter(\.isVisible)
        let aspect = referenceImageAspectRatio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let imageMaximum = NodePosition(x: aspect ?? 1, y: 1, z: aspect ?? 1)
        var lower: NodePosition
        var upper: NodePosition
        if visible.isEmpty {
            lower = NodePosition(x: 0, y: 0, z: 0)
            upper = imageMaximum
        } else {
            lower = NodePosition(
                x: visible.map { $0.value.position.x - $0.value.radius }.min() ?? 0,
                y: visible.map { $0.value.position.y - $0.value.radius }.min() ?? 0,
                z: visible.map { $0.value.position.z - $0.value.radius }.min() ?? 0)
            upper = NodePosition(
                x: visible.map { $0.value.position.x + $0.value.radius }.max() ?? 1,
                y: visible.map { $0.value.position.y + $0.value.radius }.max() ?? 1,
                z: visible.map { $0.value.position.z + $0.value.radius }.max() ?? 1)
            if aspect != nil {
                lower = .init(x: min(lower.x, 0), y: min(lower.y, 0), z: min(lower.z, 0))
                upper = .init(x: max(upper.x, imageMaximum.x), y: max(upper.y, 1), z: max(upper.z, imageMaximum.z))
            }
        }
        if let origin, [origin.x, origin.y, origin.z].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) {
            lower = .init(x: min(lower.x, origin.x), y: min(lower.y, origin.y), z: min(lower.z, origin.z))
            upper = .init(x: max(upper.x, origin.x), y: max(upper.y, origin.y), z: max(upper.z, origin.z))
        }
        minimum = lower
        maximum = upper
    }
}

public struct CanvasProjection: Equatable, Sendable {
    private let center: CanvasPoint
    private let width: Double
    private let height: Double
    public let plane: EditingPlane
    public let scale: Double

    public init(bounds: CanvasBounds, plane: EditingPlane, width: Double, height: Double) {
        self.plane = plane
        self.width = max(width, 1)
        self.height = max(height, 1)
        let lower = plane == .front ? bounds.minimum.x : bounds.minimum.z
        let upper = plane == .front ? bounds.maximum.x : bounds.maximum.z
        center = CanvasPoint(x: (lower + upper) / 2, y: (bounds.minimum.y + bounds.maximum.y) / 2)
        scale = min(
            max(self.width - 72, 1) / max(upper - lower, 0.01),
            max(self.height - 72, 1) / max(bounds.maximum.y - bounds.minimum.y, 0.01))
    }

    public func point(for position: NodePosition) -> CanvasPoint {
        CanvasPoint(
            x: width / 2 + ((plane == .front ? position.x : position.z) - center.x) * scale,
            y: height / 2 + (position.y - center.y) * scale)
    }

    /// Convert absolute canvas coordinates to a bounded document position using an explicit hidden-axis value.
    /// - Parameters: `point` is canvas-local; `hiddenCoordinate` is Z in Front and X in Side.
    /// - Throws: `invalidNode` for nonfinite/invalid projection or coordinates outside the document boundary.
    /// - Note: Native one-plane placement does not reproduce Qt's dual-profile quarter-width seed offset.
    public func position(at point: CanvasPoint, hiddenCoordinate: Double) throws -> NodePosition {
        guard [point.x, point.y, hiddenCoordinate, width, height, center.x, center.y, scale].allSatisfy(\.isFinite),
            scale > 0
        else { throw DocumentError.invalidNode }
        let horizontal = center.x + (point.x - width / 2) / scale
        let vertical = center.y + (point.y - height / 2) / scale
        let position =
            plane == .front
            ? NodePosition(x: horizontal, y: vertical, z: hiddenCoordinate)
            : NodePosition(x: hiddenCoordinate, y: vertical, z: horizontal)
        guard EditableNode(position: position, radius: 0).isValid else { throw DocumentError.invalidNode }
        return position
    }

    /// Select visible node circles that cross into the rectangle, matching Qt item-shape selection.
    public func nodeIDs(in rectangle: CanvasSelectionRectangle, nodes: [DocumentNode]) -> Set<String> {
        guard rectangle.isValid else { return [] }
        return Set(
            nodes.filter { node in
                guard node.isVisible else { return false }
                let point = point(for: node.value.position)
                guard point.x.isFinite, point.y.isFinite else { return false }
                let marker = CanvasNodeMarkerGeometry(
                    projectedDiameter: node.value.radius * scale * 2, selected: false, hovered: false)
                let x = max(rectangle.minimum.x - point.x, 0, point.x - rectangle.maximum.x)
                let y = max(rectangle.minimum.y - point.y, 0, point.y - rectangle.maximum.y)
                return hypot(x, y) < marker.marqueeRadius
            }.map(\.id))
    }

    /// Select visible native edge strokes intersecting the marquee, including boundary touches and collapsed projections.
    /// - Parameters: `rectangle` is a finite screen region; graph snapshots supply endpoints; `selectedEdgeIDs` use the native 4-point stroke (others use 2 points).
    /// - Returns: Explicit edge identities, never inferred merely because endpoint nodes were selected.
    /// - Example: `projection.edgeIDs(in: marquee, nodes: snapshot.nodes, edges: snapshot.edges)`.
    public func edgeIDs(
        in rectangle: CanvasSelectionRectangle, nodes: [DocumentNode], edges: [DocumentEdge],
        selectedEdgeIDs: Set<String> = []
    ) -> Set<String> {
        guard rectangle.isValid else { return [] }
        let positions = Dictionary(
            uniqueKeysWithValues: nodes.filter(\.isVisible).map {
                ($0.id, point(for: $0.value.position))
            })
        func intersects(_ from: CanvasPoint, _ to: CanvasPoint, halfStroke: Double) -> Bool {
            guard [from.x, from.y, to.x, to.y].allSatisfy(\.isFinite) else { return false }
            let deltaX = to.x - from.x
            let deltaY = to.y - from.y
            let length = hypot(deltaX, deltaY)
            if length == 0 {
                let x = max(rectangle.minimum.x - from.x, 0, from.x - rectangle.maximum.x)
                let y = max(rectangle.minimum.y - from.y, 0, from.y - rectangle.maximum.y)
                return hypot(x, y) <= halfStroke
            }
            guard length.isFinite else { return false }
            let tangentX = deltaX / length
            let tangentY = deltaY / length
            let normalX = -tangentY
            let normalY = tangentX
            let halfWidth = rectangle.maximum.x / 2 - rectangle.minimum.x / 2
            let halfHeight = rectangle.maximum.y / 2 - rectangle.minimum.y / 2
            let offsetX = rectangle.minimum.x / 2 + rectangle.maximum.x / 2 - from.x / 2 - to.x / 2
            let offsetY = rectangle.minimum.y / 2 + rectangle.maximum.y / 2 - from.y / 2 - to.y / 2
            // Separating axes of the marquee and the native butt-capped stroke rectangle.
            for (axisX, axisY) in [(1.0, 0.0), (0.0, 1.0), (tangentX, tangentY), (normalX, normalY)] {
                let distance = abs(offsetX * axisX + offsetY * axisY)
                let marqueeRadius = halfWidth * abs(axisX) + halfHeight * abs(axisY)
                let strokeRadius =
                    length / 2 * abs(tangentX * axisX + tangentY * axisY)
                    + halfStroke * abs(normalX * axisX + normalY * axisY)
                if distance > marqueeRadius + strokeRadius { return false }
            }
            return true
        }
        return Set(
            edges.compactMap { edge in
                guard let from = positions[edge.fromID], let to = positions[edge.toID],
                    intersects(from, to, halfStroke: selectedEdgeIDs.contains(edge.id) ? 2 : 1)
                else {
                    return nil
                }
                return edge.id
            })
    }

    /// Pick the nearest visible segment within a finite, nonnegative screen-point tolerance.
    /// Ties follow document edge order. Degenerate projections and missing/hidden endpoints are ignored.
    public func edgeID(
        near point: CanvasPoint, nodes: [DocumentNode], edges: [DocumentEdge], tolerance: Double = 8
    ) -> String? {
        guard point.x.isFinite, point.y.isFinite, tolerance.isFinite, tolerance >= 0 else { return nil }
        let positions = Dictionary(
            uniqueKeysWithValues: nodes.filter(\.isVisible).map { ($0.id, self.point(for: $0.value.position)) })
        return Self.edgeID(near: point, positions: positions, edges: edges, tolerance: tolerance)
    }

    /// Reuse projected endpoints when hit-testing the same graph repeatedly.
    package static func edgeID(
        near point: CanvasPoint, positions: [String: CanvasPoint], edges: [DocumentEdge], tolerance: Double = 8
    ) -> String? {
        guard point.x.isFinite, point.y.isFinite, tolerance.isFinite, tolerance >= 0 else { return nil }
        var nearest: String?
        var minimumDistance = tolerance
        for edge in edges {
            guard let from = positions[edge.fromID], let to = positions[edge.toID] else { continue }
            let x = to.x - from.x
            let y = to.y - from.y
            let lengthSquared = x * x + y * y
            guard lengthSquared > 0, lengthSquared.isFinite else { continue }
            let fraction = max(0, min(1, ((point.x - from.x) * x + (point.y - from.y) * y) / lengthSquared))
            let distance =
                ((point.x - from.x - fraction * x) * (point.x - from.x - fraction * x)
                + (point.y - from.y - fraction * y) * (point.y - from.y - fraction * y)).squareRoot()
            if distance <= tolerance && (nearest == nil || distance < minimumDistance) {
                nearest = edge.id
                minimumDistance = distance
            }
        }
        return nearest
    }

    /// Convert a screen gesture into model units while preserving the third axis.
    public func moving(_ position: NodePosition, by delta: CanvasPoint, locks: Set<EditingConstraint> = [])
        -> NodePosition
    {
        NodePosition(
            x: position.x + (plane == .front && !locks.contains(.x) ? delta.x / scale : 0),
            y: position.y + (locks.contains(.y) ? 0 : delta.y / scale),
            z: position.z + (plane == .side && !locks.contains(.z) ? delta.x / scale : 0))
    }
}
