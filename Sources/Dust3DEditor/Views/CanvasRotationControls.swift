import SwiftUI

/// Explicit angular input shares the captured canvas command used by keyboard/menu actions.
struct CanvasRotationControls: View {
    let store: EditorStore
    @State private var draft = "1"

    var body: some View {
        let degrees = CanvasRotationInput.angle(from: draft)
        let commit = store.canvasRotationHandler()
        let submit = {
            if let angle = CanvasRotationInput.angle(from: draft) { commit(angle) }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Rotate in \(store.plane.rawValue)").font(.headline)
            HStack {
                Button("Rotate −1°", action: store.canvasRotationAction(degrees: -1))
                Button("Rotate +1°", action: store.canvasRotationAction(degrees: 1))
            }
            HStack {
                Text("Angle (°)")
                TextField("Degrees", text: $draft)
                    .onSubmit(submit)
                    .focusedValue(\.editorTextEditing, true)
                    .accessibilityLabel("Rotation angle in degrees")
                Button("Apply Angle", action: submit)
                    .disabled(degrees == nil)
            }
            if degrees == nil {
                Text("Enter a finite angle between −2147483647° and 2147483647°.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(
                "Positive angles turn clockwise. One selected pivot with a stored origin rotates its connected descendants. Axis and part locks apply."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!store.canRotateCanvasSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas rotation, \(store.plane.rawValue)")
    }
}
