import Dust3DDocument

/// Captures a degree-one endpoint and its chain up to a branch or a fixed joint.
public struct EndpointIKDrag: Sendable {
    private let target: CanvasAdjustmentTarget
    private let chain: [DocumentNode]
    private let locks: Set<EditingConstraint>
    public let projection: CanvasProjection

    public init?(endpointID: String, snapshot: EditorSnapshot, projection: CanvasProjection) {
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
        self.projection = projection
    }

    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { target.isCurrent(in: snapshot) }

    public func updates(by translation: CanvasPoint) throws -> [NodeUpdate] {
        guard translation.x.isFinite, translation.y.isFinite else { throw DocumentError.invalidNode }
        guard translation.x != 0 || translation.y != 0, let endpoint = chain.last else { return [] }
        let axes: [(EditingConstraint, SIMD3<Double>)] = [(.x, [1, 0, 0]), (.y, [0, 1, 0]), (.z, [0, 0, 1])]
        let fixedAxes = axes.filter { locks.contains($0.0) }
        guard fixedAxes.count < 2 else { return [] }

        let destination = projection.moving(endpoint.value.position, by: translation, locks: locks)
        guard EditableNode(position: destination, radius: endpoint.value.radius).isValid else {
            throw DocumentError.invalidNode
        }
        guard destination != endpoint.value.position else { return [] }
        let positions = chain.map { node in
            let point = node.value.position
            return SIMD3<Double>(point.x, point.y, point.z)
        }
        let solved = try EndpointIK.solve(
            positions, toward: SIMD3(destination.x, destination.y, destination.z), fixedAxis: fixedAxes.first?.1)
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
