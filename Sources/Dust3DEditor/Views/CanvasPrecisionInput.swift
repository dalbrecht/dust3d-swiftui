import AppKit

/// Logical scene-point commands. Conversion uses the originating canvas height, never its fit scale.
enum CanvasPrecisionAction: CaseIterable, Hashable, Sendable {
    case left, right, up, down, increaseSpacing, decreaseSpacing

    var isSpacing: Bool { self == .increaseSpacing || self == .decreaseSpacing }
    var label: String {
        switch self {
        case .left: "Nudge Left"
        case .right: "Nudge Right"
        case .up: "Nudge Up"
        case .down: "Nudge Down"
        case .increaseSpacing: "Increase Selection Spacing"
        case .decreaseSpacing: "Decrease Selection Spacing"
        }
    }
}

/// Only actual bare arrow/bracket events belong to this responder boundary.
struct CanvasPrecisionKeyInput {
    let keyCode: UInt16
    let characters: String
    let modifiers: NSEvent.ModifierFlags
    init(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
    }
    init(_ event: NSEvent) {
        self.init(keyCode: event.keyCode, characters: event.characters ?? "", modifiers: event.modifierFlags)
    }
    var action: CanvasPrecisionAction? {
        guard modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return nil }
        switch keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default:
            switch characters {
            case "[": return .decreaseSpacing
            case "]": return .increaseSpacing
            default: return nil
            }
        }
    }
}
