import Dust3DDocument

/// Basic selection transforms and alignment to the editable selection centroid. X/Z exchange follows Qt's direct exchange and bypasses axis locks.
public enum SelectionTransform: String, CaseIterable, Sendable {
    case frontClockwise = "Front: Rotate Clockwise 90°"
    case frontCounterclockwise = "Front: Rotate Counterclockwise 90°"
    case sideClockwise = "Side: Rotate Clockwise 90°"
    case sideCounterclockwise = "Side: Rotate Counterclockwise 90°"
    case flipX = "Flip X"
    case flipY = "Flip Y"
    case flipZ = "Flip Z"
    case exchangeXZ = "Exchange X/Z (ignores axis locks)"

    case frontAlignX = "Front: Align X to Selection Center"
    case frontAlignY = "Front: Align Y to Selection Center"
    case frontAlignCenter = "Front: Align X/Y to Selection Center"
    case sideAlignZ = "Side: Align Z to Selection Center"
    case sideAlignY = "Side: Align Y to Selection Center"
    case sideAlignCenter = "Side: Align Z/Y to Selection Center"

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
        case .frontAlignX: .init(x: center.x, y: position.y, z: position.z)
        case .frontAlignY, .sideAlignY: .init(x: position.x, y: center.y, z: position.z)
        case .frontAlignCenter: .init(x: center.x, y: center.y, z: position.z)
        case .sideAlignZ: .init(x: position.x, y: position.y, z: center.z)
        case .sideAlignCenter: .init(x: position.x, y: center.y, z: center.z)
        }
    }
}
