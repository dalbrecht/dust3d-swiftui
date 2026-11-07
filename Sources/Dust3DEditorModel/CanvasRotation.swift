import Dust3DDocument
import Foundation

extension EditorSnapshot {
    package func canRotateSelection(in plane: EditingPlane) -> Bool {
        let horizontal: EditingConstraint = plane == .front ? .x : .z
        guard !locks.contains(.y) || !locks.contains(horizontal) else { return false }
        let effective = transformNodes
        // A single selected pivot needs the stored origin to choose descendants.
        return (effective.count != 1 || origin != nil) && effective.contains(where: \.isEditable)
    }
}

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
        let current = snapshot
        let updates = try CanvasRotation.updates(
            degrees: degrees, plane: plane, snapshot: current, effective: current.transformNodes)
        if !updates.isEmpty { try apply([.setNodes(updates)]) }
    }
}

enum CanvasRotation {
    static func updates(
        degrees: Double, plane: EditingPlane, snapshot current: EditorSnapshot, effective: [DocumentNode]
    ) throws -> [NodeUpdate] {
        guard degrees.isFinite, abs(degrees) <= Double(Int32.max) else { throw EditorError.invalidRotation }
        let angle = degrees.truncatingRemainder(dividingBy: 360)
        guard angle != 0 else { return [] }
        guard !effective.isEmpty else { return [] }
        let center: NodePosition
        let nodes: [DocumentNode]
        if effective.count == 1, let pivot = effective.first {
            guard pivot.isEditable else { throw EditorError.readOnlyNode }
            guard let origin = current.origin else { return [] }
            center = pivot.value.position
            let ids = DescendantRotation.frontClockwise.descendantIDs(
                pivot: pivot, origin: origin, nodes: current.nodes, edges: current.edges)
            nodes = current.nodes.filter { ids.contains($0.id) && $0.id != pivot.id && $0.isEditable }
        } else {
            nodes = effective.filter(\.isEditable)
            guard !nodes.isEmpty else { return [] }
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
        return nodes.map { node in
            let original = node.value.position
            let horizontal = plane == .front ? original.x - center.x : original.z - center.z
            let vertical = original.y - center.y
            let x = horizontal * cosine - vertical * sine
            let y = horizontal * sine + vertical * cosine
            let position = NodePosition(
                x: plane == .front && !current.locks.contains(.x) ? center.x + x : original.x,
                y: current.locks.contains(.y) ? original.y : center.y + y,
                z: plane == .side && !current.locks.contains(.z) ? center.z + x : original.z)
            return NodeUpdate(id: node.id, value: .init(position: position, radius: node.value.radius))
        }
    }
}

/// Signed world-axis rotation in the plane orthogonal to the active canvas profile.
package enum OrthogonalQuarterTurn: Int, Sendable {
    case positive = 1
    case negative = -1

    fileprivate static func participants(in snapshot: EditorSnapshot, from profile: EditingPlane) -> [DocumentNode] {
        let horizontal: EditingConstraint = profile == .front ? .z : .x
        guard !snapshot.selectedIDs.isEmpty,
            !snapshot.locks.contains(.y) || !snapshot.locks.contains(horizontal)
        else { return [] }
        let nodes = snapshot.transformNodes
        return nodes.count > 1 ? nodes : []
    }
}

extension EditorSnapshot {
    package func canRotateOrthogonalQuarterTurn(from profile: EditingPlane) -> Bool {
        OrthogonalQuarterTurn.participants(in: self, from: profile).contains(where: \.isEditable)
    }
}

extension EditorState {
    package mutating func rotateOrthogonalQuarterTurn(
        _ turn: OrthogonalQuarterTurn, from profile: EditingPlane, target: CanvasAdjustmentTarget? = nil
    ) throws {
        let current = snapshot
        if let target, !target.isCurrent(in: current) { throw EditorError.staleCanvasAdjustment }
        let nodes = OrthogonalQuarterTurn.participants(in: current, from: profile)
        guard !nodes.isEmpty else { return }

        // Read-only participants still contribute to the Qt centroid.
        let center = NodePosition(
            x: nodes.reduce(0) { $0 + $1.value.position.x } / Double(nodes.count),
            y: nodes.reduce(0) { $0 + $1.value.position.y } / Double(nodes.count),
            z: nodes.reduce(0) { $0 + $1.value.position.z } / Double(nodes.count))
        let sign = Double(turn.rawValue)
        let updates = nodes.compactMap { node -> NodeUpdate? in
            guard node.isEditable else { return nil }
            let original = node.value.position
            let vertical = original.y - center.y
            let position: NodePosition
            switch profile {
            case .front:
                position = NodePosition(
                    x: original.x,
                    y: current.locks.contains(.y) ? original.y : center.y - sign * (original.z - center.z),
                    z: current.locks.contains(.z) ? original.z : center.z + sign * vertical)
            case .side:
                position = NodePosition(
                    x: current.locks.contains(.x) ? original.x : center.x + sign * vertical,
                    y: current.locks.contains(.y) ? original.y : center.y - sign * (original.x - center.x),
                    z: original.z)
            }
            guard position != original else { return nil }
            return NodeUpdate(id: node.id, value: .init(position: position, radius: node.value.radius))
        }
        if !updates.isEmpty { try apply([.setNodes(updates)]) }
    }
}
