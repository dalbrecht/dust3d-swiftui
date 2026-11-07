import AppKit

/// Qt's Add and Select keys belong to the focused canvas, leaving native text and command chords alone.
enum CanvasAddModeKey: Equatable {
    case ignored
    case toggleAdd
    case select
    case consumeRepeat

    typealias Handler = (Self, CanvasProfileFocusRequest?) -> Bool

    static func disposition(characters: String, modifiers: NSEvent.ModifierFlags, isRepeat: Bool) -> Self {
        let disallowed: NSEvent.ModifierFlags = [.command, .shift, .option, .control, .function]
        guard modifiers.intersection(disallowed).isEmpty else { return .ignored }
        switch characters {
        case "a", "A": return isRepeat ? .consumeRepeat : .toggleAdd
        case "s", "S": return isRepeat ? .consumeRepeat : .select
        default: return .ignored
        }
    }

    @MainActor static func route(_ event: NSEvent, in window: NSWindow, handle: Handler?) -> Bool {
        guard let handle, window.isKeyWindow, window.attachedSheet == nil else { return false }
        let key = disposition(
            characters: event.characters ?? "", modifiers: event.modifierFlags, isRepeat: event.isARepeat)
        switch key {
        case .ignored: return false
        case .consumeRepeat: return handle(key, nil)
        case .toggleAdd, .select: return handle(key, CanvasProfileFocusRequest(window: window))
        }
    }
}
