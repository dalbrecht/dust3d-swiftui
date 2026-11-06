import Dust3DDocument

/// Captures a degree-one endpoint and its chain up to a branch or a fixed joint.
public struct EndpointIKTarget: Sendable {
    private let target: CanvasAdjustmentTarget
    private let chain: [DocumentNode]
    private let locks: Set<EditingConstraint>
    public let endpointPosition: NodePosition
    public var canBend: Bool { locks.intersection([.x, .y, .z]).count < 2 }

    public init?(endpointID: String, snapshot: EditorSnapshot) {
        let nodes = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
        guard let endpoint = nodes[endpointID], endpoint.isEditable else { return nil }
        var neighbors: [String: [String]] = [:]
        for edge in snapshot.edges {
            neighbors[edge.fromID, default: []].append(edge.toID)
            neighbors[edge.toID, default: []].append(edge.fromID)
        }
        guard neighbors[endpointID]?.count == 1 else { return nil }

        var visited = Set([endpointID])
        var joints = [endpoint]
        var cursor = endpoint
        while cursor.isEditable, let adjacent = neighbors[cursor.id], adjacent.count <= 2,
            let next = adjacent.first(where: { !visited.contains($0) }), let joint = nodes[next]
        {
            visited.insert(next)
            joints.append(joint)
            cursor = joint
        }
        guard joints.count > 1 else { return nil }
        chain = joints.reversed()
        target = CanvasAdjustmentTarget(snapshot: snapshot)
        locks = snapshot.locks
        endpointPosition = endpoint.value.position
    }

    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { target.isCurrent(in: snapshot) }

    public func updates(toward requested: NodePosition) throws -> [NodeUpdate] {
        guard [requested.x, requested.y, requested.z].allSatisfy(\.isFinite) else {
            throw DocumentError.invalidNode
        }
        guard canBend else { return [] }
        let destination = NodePosition(
            x: locks.contains(.x) ? endpointPosition.x : requested.x,
            y: locks.contains(.y) ? endpointPosition.y : requested.y,
            z: locks.contains(.z) ? endpointPosition.z : requested.z)
        guard EditableNode(position: destination, radius: 0).isValid else { throw DocumentError.invalidNode }
        guard destination != endpointPosition else { return [] }
        let axes: [(EditingConstraint, SIMD3<Double>)] = [(.x, [1, 0, 0]), (.y, [0, 1, 0]), (.z, [0, 0, 1])]
        let fixedAxis = axes.first { locks.contains($0.0) }?.1
        let positions = chain.map { node in
            let point = node.value.position
            return SIMD3<Double>(point.x, point.y, point.z)
        }
        let solved = try EndpointIK.solve(
            positions, toward: SIMD3(destination.x, destination.y, destination.z), fixedAxis: fixedAxis)
        return zip(chain.dropFirst(), solved.dropFirst()).compactMap { node, point in
            let original = node.value.position
            let position = NodePosition(
                x: locks.contains(.x) ? original.x : point.x,
                y: locks.contains(.y) ? original.y : point.y,
                z: locks.contains(.z) ? original.z : point.z)
            guard position != original else { return nil }
            return NodeUpdate(id: node.id, value: EditableNode(position: position, radius: node.value.radius))
        }
    }
}
