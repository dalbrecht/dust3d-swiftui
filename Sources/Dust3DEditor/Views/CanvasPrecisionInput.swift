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
    var partShapeShortcut: CanvasPartShapeShortcut? {
        guard isBareEditingKey else { return nil }
        return CanvasPartShapeShortcut(rawValue: characters.lowercased())
    }

    @MainActor func permitsDispatch(in window: NSWindow) -> Bool {
        guard axisLockConstraint != nil || partStateProperty != nil || partShapeShortcut != nil else { return true }
        return window.isKeyWindow && window.attachedSheet == nil && window.sheetParent == nil
            && NSApp.modalWindow == nil
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
