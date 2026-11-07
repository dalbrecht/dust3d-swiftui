import Dust3DDocument

/// Model-space radius bounds for explicit origin placement, independent of visibility and selection.
public enum OriginSettlement {
    /// Compute Qt-compatible radius-bound center from all supplied nodes. Empty input returns zero.
    /// - Parameter nodes: Every document node, including hidden, locked and disabled parts.
    /// - Returns: The center of the X/Y/Z radius-bound union, without changing geometry.
    /// - Throws: `DocumentError.invalidNode` for nonfinite, negative-radius or oversized geometry.
    public static func center(of nodes: [EditableNode]) throws -> NodePosition {
        try DocumentOriginSettlement.center(of: nodes)
    }
}
