import AppKit

/// Bare E is handled only by an idle canvas responder, never by a global shortcut.
enum CanvasProfileSwitchKey: Equatable {
    case ignored
    case switchProfile
    case consumeRepeat

    static func disposition(characters: String, modifiers: NSEvent.ModifierFlags, isRepeat: Bool) -> Self {
        let disallowed: NSEvent.ModifierFlags = [.command, .shift, .option, .control, .function]
        guard modifiers.intersection(disallowed).isEmpty, characters == "e" || characters == "E" else {
            return .ignored
        }
        return isRepeat ? .consumeRepeat : .switchProfile
    }

    @MainActor
    static func route(
        _ event: NSEvent, in window: NSWindow, switchProfile: ((CanvasProfileFocusRequest) -> Bool)?
    ) -> Bool {
        guard let switchProfile, window.isKeyWindow else { return false }
        switch disposition(
            characters: event.characters ?? "", modifiers: event.modifierFlags, isRepeat: event.isARepeat)
        {
        case .ignored: return false
        case .consumeRepeat: return true
        case .switchProfile: return switchProfile(CanvasProfileFocusRequest(window: window))
        }
    }
}
