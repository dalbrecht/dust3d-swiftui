import Dust3DEditorModel
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

@MainActor struct OrthogonalQuarterTurnActions {
    let axis: String
    let positive: (@MainActor () -> Void)?
    let negative: (@MainActor () -> Void)?

    init(store: EditorStore?, profileLease: UUID? = nil) {
        axis = store?.plane == .side ? "Z" : "X"
        positive = store?.orthogonalQuarterTurnAction(.positive, profileLease: profileLease)
        negative = store?.orthogonalQuarterTurnAction(.negative, profileLease: profileLease)
    }
}

struct OrthogonalQuarterTurnMenu: View {
    let actions: OrthogonalQuarterTurnActions
    var contextual = false

    var body: some View {
        if !contextual || actions.positive != nil {
            Menu("Rotate Around \(actions.axis) Axis") {
                Button("Rotate +90°") { actions.positive?() }.disabled(actions.positive == nil)
                Button("Rotate −90°") { actions.negative?() }.disabled(actions.negative == nil)
            }
            .disabled(actions.positive == nil)
        }
    }
}
