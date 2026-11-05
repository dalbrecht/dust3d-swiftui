import AppKit

/// Radius keys belong to a focused canvas responder, never to the scene's menu key equivalents.
enum CanvasRadiusKey {
    static func direction(for event: NSEvent) -> Int? {
        guard event.type == .keyDown,
            event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        else { return nil }
        switch event.charactersIgnoringModifiers {
        case "-": return -1
        case "=": return 1
        default: return nil
        }
    }
}
