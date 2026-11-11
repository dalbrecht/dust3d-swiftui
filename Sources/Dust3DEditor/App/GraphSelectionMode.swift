import AppKit

/// Pointer and accessible selection routes use the same atomic session operations.
enum GraphSelectionMode {
    case replace, add, toggle, subtract

    /// Copy modifier intent at press time; release-time changes cannot retarget a gesture.
    static func pointerMode(modifiers: NSEvent.ModifierFlags) -> Self {
        if modifiers.contains([.command, .option]) { return .subtract }
        if modifiers.contains(.command) { return .toggle }
        return modifiers.contains(.shift) ? .add : .replace
    }
}

/// A rendered node can select itself or expand selection to its owning part.
enum CanvasNodeSelectionAction {
    case pointerReplace
    case selection(GraphSelectionMode)
    case wholePart
}
