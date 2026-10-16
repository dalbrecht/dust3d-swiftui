import Dust3DDocument

/// Model-space radius bounds for explicit origin placement, independent of visibility and selection.
public enum OriginSettlement {
    /// Compute Qt-compatible radius-bound center from all supplied nodes. Empty input returns zero.
    /// - Parameter nodes: Every document node, including hidden, locked and disabled parts.
    /// - Returns: The center of the X/Y/Z radius-bound union, without changing geometry.
    /// - Throws: `DocumentError.invalidNode` for nonfinite, negative-radius or oversized geometry.
    public static func center(of nodes: [EditableNode]) throws -> NodePosition {
        guard nodes.allSatisfy(\.isValid) else { throw DocumentError.invalidNode }
        guard let first = nodes.first else { return .init(x: 0, y: 0, z: 0) }
        var lower = NodePosition(
            x: first.position.x - first.radius, y: first.position.y - first.radius,
            z: first.position.z - first.radius)
        var upper = NodePosition(
            x: first.position.x + first.radius, y: first.position.y + first.radius,
            z: first.position.z + first.radius)
        for node in nodes.dropFirst() {
            lower = .init(
                x: min(lower.x, node.position.x - node.radius), y: min(lower.y, node.position.y - node.radius),
                z: min(lower.z, node.position.z - node.radius))
            upper = .init(
                x: max(upper.x, node.position.x + node.radius), y: max(upper.y, node.position.y + node.radius),
                z: max(upper.z, node.position.z + node.radius))
        }
        return .init(x: (lower.x + upper.x) / 2, y: (lower.y + upper.y) / 2, z: (lower.z + upper.z) / 2)
    }
}
