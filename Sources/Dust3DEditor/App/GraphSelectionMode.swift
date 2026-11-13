import AppKit
import Dust3DEditorModel

extension GraphSelectionMode {

    /// Copy modifier intent at press time; release-time changes cannot retarget a gesture.
    static func pointerMode(modifiers: NSEvent.ModifierFlags) -> Self {
        if modifiers.contains([.command, .option]) { return .subtract }
        if modifiers.contains(.command) { return .toggle }
        return modifiers.contains(.shift) ? .add : .replace
    }
}

/// A rendered node can select itself or expand selection to its owning part.
enum CanvasNodeSelectionAction {
    case selection(GraphSelectionMode)
    case wholePart
}
