import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct ComponentSmoothingControls: View {
    let store: EditorStore
    let component: DocumentComponent
    let target: CanvasAdjustmentTarget
    @State private var degrees = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smoothing cutoff (°)").font(.caption)
            TextField("Smoothing cutoff (°)", text: $degrees)
                .accessibilityIdentifier("component-smoothing-cutoff")
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { apply() }
            if component.smoothCutoffDegrees == nil {
                Text("Unsupported source cutoff. Enter a value to replace it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Reset Draft") { reset() }
                Spacer()
                Button("Apply Cutoff") { apply() }
            }
            Button("Set Sharp (0°)") {
                store.setComponentSmoothCutoff(component.id, degrees: "0", target: target)
            }
            .accessibilityLabel("Set zero smoothing cutoff")
        }
        .disabled(!store.canSave)
        .help("Normal smoothing from 0 to 180 degrees. Zero retains sharp edges. Apply is one undo step.")
        .onChange(of: component.id, initial: true) { _, _ in reset() }
        .onChange(of: component.smoothCutoffDegrees) { _, _ in reset() }
    }

    private func reset() { degrees = component.smoothCutoffDegrees.map { String($0) } ?? "" }
    private func apply() { store.setComponentSmoothCutoff(component.id, degrees: degrees, target: target) }
}
