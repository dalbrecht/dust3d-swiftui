import Dust3DDocument

/// Converts numeric inspector drafts into requests for the currently editable channels.
package enum SelectionTransformInput {
    private static let positionLocks: Set<EditingConstraint> = [.x, .y, .z]

    package static func move(delta: NodePosition, locks: Set<EditingConstraint>) -> NodePosition? {
        guard !locks.isSuperset(of: positionLocks) else { return nil }
        let effective = NodePosition(
            x: locks.contains(.x) ? 0 : delta.x,
            y: locks.contains(.y) ? 0 : delta.y,
            z: locks.contains(.z) ? 0 : delta.z)
        guard effective.x.isFinite, effective.y.isFinite, effective.z.isFinite else { return nil }
        return effective
    }

    package static func scale(
        positionFactor: Double, radiusFactor: Double, locks: Set<EditingConstraint>
    ) -> (positionFactor: Double, radiusFactor: Double)? {
        let positionsLocked = locks.isSuperset(of: positionLocks)
        let radiiLocked = locks.contains(.radius)
        guard !positionsLocked || !radiiLocked else { return nil }
        let position = positionsLocked ? 1 : positionFactor
        let radius = radiiLocked ? 1 : radiusFactor
        guard position.isFinite, position > 0, radius.isFinite, radius > 0 else { return nil }
        return (position, radius)
    }
}
