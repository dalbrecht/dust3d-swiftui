import AppKit
import Dust3DEditorModel

struct CanvasRotationContext: Hashable {
    let target: CanvasAdjustmentTarget
    let plane: EditingPlane
    let inputEpoch: UUID
    let addModeEpoch: UUID
}

/// Exact bare Qt punctuation; shifted characters and command chords remain responder-owned.
enum CanvasRotationInput {
    static func angle(from draft: String, locale: Locale = .current) -> Double? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: text)
        scanner.locale = locale
        guard !text.isEmpty, let value = scanner.scanDouble(), scanner.isAtEnd,
            value.isFinite, abs(value) <= Double(Int32.max)
        else { return nil }
        return value
    }
    @MainActor static var currentKeyboardModifiers: NSEvent.ModifierFlags {
        guard NSApp.currentEvent?.type == .keyDown else { return [] }
        return NSEvent.modifierFlags
    }
    static func degrees(
        characters: String, modifiers: NSEvent.ModifierFlags,
        animationFocus: Bool, nativeTextFocus: Bool
    ) -> Double? {
        guard EditorCommandScope.allowsGraphShortcuts(animationFocus: animationFocus, nativeTextFocus: nativeTextFocus),
            modifiers.intersection([.command, .control, .option, .shift]).isEmpty
        else { return nil }
        switch characters {
        case ",": return -1
        case ".": return 1
        default: return nil
        }
    }
}
