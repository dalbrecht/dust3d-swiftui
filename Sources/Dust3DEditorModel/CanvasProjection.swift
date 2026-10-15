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

/// Fit bounds are held stable during an edit so dragging cannot move its own coordinate system.
public struct CanvasBounds: Sendable {
    let minimum: NodePosition
    let maximum: NodePosition

    public init(nodes: [DocumentNode]) {
        let visible = nodes.filter(\.isVisible)
        if visible.isEmpty {
            minimum = NodePosition(x: 0, y: 0, z: 0)
            maximum = NodePosition(x: 1, y: 1, z: 1)
        } else {
            minimum = NodePosition(
                x: visible.map { $0.value.position.x - $0.value.radius }.min() ?? 0,
                y: visible.map { $0.value.position.y - $0.value.radius }.min() ?? 0,
                z: visible.map { $0.value.position.z - $0.value.radius }.min() ?? 0)
            maximum = NodePosition(
                x: visible.map { $0.value.position.x + $0.value.radius }.max() ?? 1,
                y: visible.map { $0.value.position.y + $0.value.radius }.max() ?? 1,
                z: visible.map { $0.value.position.z + $0.value.radius }.max() ?? 1)
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
            y: height / 2 - (position.y - center.y) * scale)
    }

    /// Convert a screen gesture into model units while preserving the third axis.
    public func moving(_ position: NodePosition, by delta: CanvasPoint, locks: Set<EditingConstraint> = [])
        -> NodePosition
    {
        NodePosition(
            x: position.x + (plane == .front && !locks.contains(.x) ? delta.x / scale : 0),
            y: position.y - (locks.contains(.y) ? 0 : delta.y / scale),
            z: position.z + (plane == .side && !locks.contains(.z) ? delta.x / scale : 0))
    }
}
