#if MOTE3D_EXPERIMENTAL_HOLLOW
    import Dust3DDocument
    import SwiftUI

    struct PartHollowControls: View {
        let store: EditorStore
        let partID: String
        @State private var draft = ""
        @State private var savedThickness = ""

        var body: some View {
            let guidance = Text("Enter a value from 0 to 1. Both 0 and 1 make the tube solid.")
            VStack(alignment: .leading, spacing: 4) {
                TextField("Hollow thickness", text: $draft)
                    .accessibilityIdentifier("part-hollow-thickness")
                    .accessibilityHint(guidance)
                    .focusedValue(\.editorTextEditing, true)
                    .onSubmit(apply)
                Button("Apply Hollow Thickness", action: apply)
                Text(
                    "Hollow preview is experimental. The standard editor preserves this value but renders a solid tube."
                )
                .font(.caption).foregroundStyle(.secondary)
                guidance.font(.caption)
            }
            .onChange(of: store.snapshot?.documentIdentity, initial: true) { _, _ in refreshDraft(reset: true) }
            .onChange(of: store.snapshot?.documentRevision) { _, _ in refreshDraft() }
        }

        private func refreshDraft(reset: Bool = false) {
            let thickness = (try? store.snapshot?.document.partHollowThicknessSource(id: partID)) ?? "0"
            guard reset || thickness != savedThickness else { return }
            savedThickness = thickness
            draft = thickness
        }

        private func apply() {
            store.setExperimentalHollowThickness(partID, value: draft)
        }
    }

#endif
