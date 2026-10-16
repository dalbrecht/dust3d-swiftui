import Dust3DDocument

/// Explicit connected-node quarter turns around one fixed pivot, with native interaction locks.
public enum DescendantRotation: String, CaseIterable, Sendable {
    case frontClockwise = "Front: Rotate Descendants Clockwise 90°"
    case frontCounterclockwise = "Front: Rotate Descendants Counterclockwise 90°"
    case sideClockwise = "Side: Rotate Descendants Clockwise 90°"
    case sideCounterclockwise = "Side: Rotate Descendants Counterclockwise 90°"

    var transform: SelectionTransform {
        switch self {
        case .frontClockwise: .frontClockwise
        case .frontCounterclockwise: .frontCounterclockwise
        case .sideClockwise: .sideClockwise
        case .sideCounterclockwise: .sideCounterclockwise
        }
    }

    /// Snapshot endpoints have already been validated by the document boundary.
    /// Source node order resolves equal-distance parents; traversal order cannot change the resulting set.
    func descendantIDs(pivot: DocumentNode, origin: NodePosition, nodes: [DocumentNode], edges: [DocumentEdge]) -> Set<
        String
    > {
        var adjacent: [String: [String]] = [:]
        for edge in edges {
            adjacent[edge.fromID, default: []].append(edge.toID)
            adjacent[edge.toID, default: []].append(edge.fromID)
        }
        let direct = Set(adjacent[pivot.id] ?? [])
        let parent =
            direct.count > 1
            ? nodes.filter { direct.contains($0.id) }.min {
                Self.distanceSquared($0.value.position, origin) < Self.distanceSquared($1.value.position, origin)
            }?.id : nil
        var pending = Array(direct.filter { $0 != parent })
        var visited: Set<String> = [pivot.id]
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else { continue }
            if let neighbors = adjacent[current] { pending.append(contentsOf: neighbors) }
        }
        return visited
    }

    private static func distanceSquared(_ position: NodePosition, _ origin: NodePosition) -> Double {
        let x = position.x - origin.x
        let y = position.y - origin.y
        let z = position.z - origin.z
        return x * x + y * y + z * z
    }
}
