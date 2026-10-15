import Dust3DDocument

/// Basic selection transforms. X/Z exchange follows Qt's direct exchange and bypasses axis locks.
public enum SelectionTransform: String, CaseIterable, Sendable {
    case frontClockwise = "Front: Rotate Clockwise 90°"
    case frontCounterclockwise = "Front: Rotate Counterclockwise 90°"
    case sideClockwise = "Side: Rotate Clockwise 90°"
    case sideCounterclockwise = "Side: Rotate Counterclockwise 90°"
    case flipX = "Flip X"
    case flipY = "Flip Y"
    case flipZ = "Flip Z"
    case exchangeXZ = "Exchange X/Z (ignores axis locks)"

    func position(_ position: NodePosition, around center: NodePosition) -> NodePosition {
        switch self {
        case .frontCounterclockwise:
            .init(x: center.x + (position.y - center.y), y: center.y - (position.x - center.x), z: position.z)
        case .frontClockwise:
            .init(x: center.x - (position.y - center.y), y: center.y + (position.x - center.x), z: position.z)
        case .sideCounterclockwise:
            .init(x: position.x, y: center.y - (position.z - center.z), z: center.z + (position.y - center.y))
        case .sideClockwise:
            .init(x: position.x, y: center.y + (position.z - center.z), z: center.z - (position.y - center.y))
        case .flipX: .init(x: 2 * center.x - position.x, y: position.y, z: position.z)
        case .flipY: .init(x: position.x, y: 2 * center.y - position.y, z: position.z)
        case .flipZ: .init(x: position.x, y: position.y, z: 2 * center.z - position.z)
        case .exchangeXZ: .init(x: position.z, y: position.y, z: position.x)
        }
    }
}
