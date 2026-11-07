import AppKit

/// Classify copied button/modifier values before a primary handler can edit or drag.
enum CanvasContextClick {
    enum Decision: Equatable { case primary, showMenu, cancelAdd, unhandled }

    static func decision(
        buttonNumber: Int, modifiers: NSEvent.ModifierFlags, isAddingNodes: Bool
    ) -> Decision {
        if buttonNumber == 0 && !modifiers.contains(.control) { return .primary }
        if buttonNumber == 1 || (buttonNumber == 0 && modifiers.contains(.control)) {
            return isAddingNodes ? .cancelAdd : .showMenu
        }
        return .unhandled
    }
}
