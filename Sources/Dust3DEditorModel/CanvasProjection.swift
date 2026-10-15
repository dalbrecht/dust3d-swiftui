import Dust3DDocument

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

    /// Fit visible nodes and, when present, an image-height-normalized reference rectangle.
    public init(nodes: [DocumentNode], referenceImageAspectRatio: Double? = nil) {
        let visible = nodes.filter(\.isVisible)
        let aspect = referenceImageAspectRatio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let imageMaximum = NodePosition(x: aspect ?? 1, y: 1, z: aspect ?? 1)
        if visible.isEmpty {
            minimum = NodePosition(x: 0, y: 0, z: 0)
            maximum = imageMaximum
        } else {
            let lower = NodePosition(
                x: visible.map { $0.value.position.x - $0.value.radius }.min() ?? 0,
                y: visible.map { $0.value.position.y - $0.value.radius }.min() ?? 0,
                z: visible.map { $0.value.position.z - $0.value.radius }.min() ?? 0)
            let upper = NodePosition(
                x: visible.map { $0.value.position.x + $0.value.radius }.max() ?? 1,
                y: visible.map { $0.value.position.y + $0.value.radius }.max() ?? 1,
                z: visible.map { $0.value.position.z + $0.value.radius }.max() ?? 1)
            minimum = aspect == nil ? lower : .init(x: min(lower.x, 0), y: min(lower.y, 0), z: min(lower.z, 0))
            maximum =
                aspect == nil
                ? upper : .init(x: max(upper.x, imageMaximum.x), y: max(upper.y, 1), z: max(upper.z, imageMaximum.z))
        }
    }

}

public struct CanvasProjection: Sendable {
    private let center: CanvasPoint
    private let width: Double
    private let height: Double
    private let plane: EditingPlane
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

    /// Select visible node centers, including centers on the rectangle boundary.
    public func nodeIDs(in rectangle: CanvasSelectionRectangle, nodes: [DocumentNode]) -> Set<String> {
        guard rectangle.isValid else { return [] }
        return Set(
            nodes.filter { node in
                let point = point(for: node.value.position)
                return node.isVisible && point.x >= rectangle.minimum.x && point.x <= rectangle.maximum.x
                    && point.y >= rectangle.minimum.y && point.y <= rectangle.maximum.y
            }.map(\.id))
    }

    /// Pick the nearest visible segment within a finite, nonnegative screen-point tolerance.
    /// Ties follow document edge order. Degenerate projections and missing/hidden endpoints are ignored.
    public func edgeID(
        near point: CanvasPoint, nodes: [DocumentNode], edges: [DocumentEdge], tolerance: Double = 8
    ) -> String? {
        guard [point.x, point.y, tolerance].allSatisfy(\.isFinite), tolerance >= 0 else { return nil }
        let positions = Dictionary(
            uniqueKeysWithValues: nodes.filter(\.isVisible).map { ($0.id, self.point(for: $0.value.position)) })
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
