import Dust3DDocument
import Foundation

extension EditorState {
    /// Rotate the explicit graph's merged node/edge-endpoint set in one undo transaction.
    /// A single effective node with a supported stored origin pivots its connected descendants;
    /// otherwise editable participants rotate about their centroid. Native axis/part locks apply.
    /// - Parameters:
    ///   - degrees: Finite signed angle within Qt's signed 32-bit degree range. Full turns are no-ops.
    ///   - plane: Front X/Y or Side Z/Y; positive angles turn clockwise in the native canvas.
    ///   - target: Optional captured document, selection and constraint epochs.
    /// - Throws: Typed stale, angle, readonly pivot or document geometry errors atomically.
    public mutating func rotateSelection(
        degrees: Double, plane: EditingPlane, target: CanvasAdjustmentTarget? = nil
    ) throws {
        if let target, !target.isCurrent(in: snapshot) { throw EditorError.staleCanvasAdjustment }
        guard degrees.isFinite, abs(degrees) <= Double(Int32.max) else { throw EditorError.invalidRotation }
        let angle = degrees.truncatingRemainder(dividingBy: 360)
        guard angle != 0 else { return }
        let current = snapshot
        let effective = current.transformNodes
        guard !effective.isEmpty else { return }
        let center: NodePosition
        let nodes: [DocumentNode]
        if effective.count == 1, let pivot = effective.first {
            guard pivot.isEditable else { throw EditorError.readOnlyNode }
            guard let origin = current.origin else { return }
            center = pivot.value.position
            let ids = DescendantRotation.frontClockwise.descendantIDs(
                pivot: pivot, origin: origin, nodes: current.nodes, edges: current.edges)
            nodes = current.nodes.filter { ids.contains($0.id) && $0.id != pivot.id && $0.isEditable }
        } else {
            nodes = effective.filter(\.isEditable)
            guard !nodes.isEmpty else { return }
            let count = Double(nodes.count)
            center = .init(
                x: nodes.reduce(0) { $0 + $1.value.position.x } / count,
                y: nodes.reduce(0) { $0 + $1.value.position.y } / count,
                z: nodes.reduce(0) { $0 + $1.value.position.z } / count)
        }
        // Exact quarter turns avoid accumulated trigonometric roundoff at cardinal angles.
        let sine: Double
        let cosine: Double
        switch angle {
        case 90, -270: (sine, cosine) = (1, 0)
        case -90, 270: (sine, cosine) = (-1, 0)
        case 180, -180: (sine, cosine) = (0, -1)
        default:
            let radians = angle * .pi / 180
            (sine, cosine) = (sin(radians), cos(radians))
        }
        let updates = nodes.map { node in
            let original = node.value.position
            let horizontal = plane == .front ? original.x - center.x : original.z - center.z
            let vertical = original.y - center.y
            let x = horizontal * cosine - vertical * sine
            let y = horizontal * sine + vertical * cosine
            let position = NodePosition(
                x: plane == .front ? center.x + x : original.x,
                y: center.y + y,
                z: plane == .side ? center.z + x : original.z)
            return NodeUpdate(id: node.id, value: .init(position: position, radius: node.value.radius))
        }
        try apply([.setNodes(updates)])
    }
}
