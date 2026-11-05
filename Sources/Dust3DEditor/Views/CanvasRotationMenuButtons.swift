import SwiftUI

struct CanvasRotationMenuButtons: View {
    let store: EditorStore?
    let animationFocus: Bool
    let nativeTextFocus: Bool

    var body: some View {
        ForEach([",", "."], id: \.self) { key in
            Button(key == "," ? "Rotate Selection −1°" : "Rotate Selection +1°") {
                store?.handleCanvasRotationInput(
                    characters: key, modifiers: CanvasRotationInput.currentKeyboardModifiers,
                    animationFocus: animationFocus, nativeTextFocus: nativeTextFocus)
            }
            .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: [])
            .disabled(
                !EditorCommandScope.allowsGraphShortcuts(
                    animationFocus: animationFocus, nativeTextFocus: nativeTextFocus)
                    || store?.canRotateCanvasSelection != true)
        }
    }
}
