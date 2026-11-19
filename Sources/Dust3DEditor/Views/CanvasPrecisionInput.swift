import AppKit
import Dust3DDocument
import Dust3DEditorModel

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

enum CanvasPartShapeShortcut: String, CaseIterable {
    case subdivision = "b"
    case roundedEnds = "u"
    case chamfer = "c"

    var property: PartModifierProperty {
        switch self {
        case .subdivision: .subdivision
        case .roundedEnds: .roundedEnds
        case .chamfer: .chamfer
        }
    }

    var title: String {
        switch self {
        case .subdivision: "Toggle Subdivision"
        case .roundedEnds: "Toggle Rounded Ends"
        case .chamfer: "Toggle Chamfer"
        }
    }

    var keyLabel: String { rawValue.uppercased() }
}

enum CanvasVisibilityShortcut: Equatable {
    case toggle
    case isolate
}

/// Routes canvas navigation and bare graph editing keys at the canvas responder boundary.

struct CanvasPrecisionKeyInput {
    let keyCode: UInt16
    let characters: String
    let modifiers: NSEvent.ModifierFlags
    let isRepeat: Bool
    init(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags, isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
    init(_ event: NSEvent) {
        self.init(
            keyCode: event.keyCode, characters: event.characters ?? "", modifiers: event.modifierFlags,
            isRepeat: event.isARepeat)
    }
    private var isBareEditingKey: Bool {
        modifiers.intersection([.command, .control, .option, .shift, .function]).isEmpty
    }

    var isAlternateDelete: Bool {
        let editingModifiers = modifiers.intersection([.command, .control, .option, .shift, .function])
        if characters == "\u{7F}" {  // AppKit's character for the keyboard Delete key
            return editingModifiers.isEmpty
        }
        if characters == "\u{F728}" {  // AppKit's forward-delete function character
            return editingModifiers.isEmpty || editingModifiers == .function
        }
        return editingModifiers == .control && (characters == "\u{4}" || characters == "d")
    }

    var axisLockConstraint: EditingConstraint? {
        guard isBareEditingKey else { return nil }
        switch characters {
        case "x", "X": return .x
        case "y", "Y": return .y
        case "z", "Z": return .z
        default: return nil
        }
    }
    var partStateProperty: PartStateProperty? {
        guard isBareEditingKey else { return nil }
        switch characters {
        case "j", "J": return .disabled
        case "l", "L": return .locked
        default: return nil
        }
    }
    @MainActor static func permitsDispatch(in window: NSWindow) -> Bool {
        window.isKeyWindow && window.attachedSheet == nil && window.sheetParent == nil
            && NSApp.modalWindow == nil
    }

    var partShapeShortcut: CanvasPartShapeShortcut? {
        guard isBareEditingKey else { return nil }
        return CanvasPartShapeShortcut(rawValue: characters.lowercased())
    }

    var visibilityShortcut: CanvasVisibilityShortcut? {
        guard modifiers.intersection([.command, .control, .option, .function]).isEmpty,
            characters == "h" || characters == "H"
        else { return nil }
        return modifiers.contains(.shift) ? .isolate : .toggle

    }

    var opensComponentProperties: Bool { isBareEditingKey && characters == " " }

    var selectsOwningComponent: Bool { isBareEditingKey && (characters == "f" || characters == "F") }

    @MainActor func permitsDispatch(in window: NSWindow) -> Bool {
        guard
            axisLockConstraint != nil || partStateProperty != nil || selectsOwningComponent || opensComponentProperties
                || isAlternateDelete || partShapeShortcut != nil || visibilityShortcut != nil

        else { return true }
        return window.isKeyWindow && window.attachedSheet == nil && window.sheetParent == nil
            && NSApp.modalWindow == nil
    }

    private var isSelectionPropertiesShortcut: Bool {
        characters == " " && modifiers.intersection([.command, .control, .option, .shift, .function]).isEmpty
    }

    var requiresActiveCanvasWindow: Bool { partStateProperty != nil || isSelectionPropertiesShortcut }

    @MainActor
    func routeSelectionProperties(action: (@MainActor () -> Bool)?) -> Bool {
        guard isSelectionPropertiesShortcut, let action else { return false }
        return isRepeat || action()
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
