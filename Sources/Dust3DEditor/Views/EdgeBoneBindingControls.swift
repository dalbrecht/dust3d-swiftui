import Dust3DDocument
import SwiftUI

struct EdgeBoneBindingControls: View {
    let store: EditorStore
    let edge: DocumentEdge
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bone assignment").font(.headline)
            TextField("Unassigned", text: $draft)
                .frame(minHeight: 40)
                .accessibilityLabel("Bone name")
                .accessibilityIdentifier("edge-bone-name")
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { apply() }
                .onExitCommand { reset() }
            HStack {
                Button(action: reset) { Text("Reset Draft").frame(minHeight: 32) }
                    .accessibilityLabel("Reset bone name draft")
                Spacer()
                Button {
                    store.setEdgeBoneName(edge.id, name: "")
                } label: {
                    Text("Clear").frame(minHeight: 32)
                }
                .accessibilityLabel("Clear bone assignment")
                .disabled(edge.boneName.isEmpty)
                Button(action: apply) { Text("Apply").frame(minHeight: 32) }
                    .accessibilityLabel("Apply bone assignment")
                    .disabled(draft == edge.boneName)
            }
            Text("Use the exact bone name. Each applied change is one undo step.")
                .font(.caption).foregroundStyle(.primary)
            Text("Assignments are saved with the document. Rigged preview is not available in this build.")
                .font(.caption).foregroundStyle(.primary)
        }
        .disabled(store.isWorking || store.snapshot?.canEditSelectedEdge != true)
        .onChange(of: edge.id, initial: true) { _, _ in reset() }
        .onChange(of: edge.boneName) { _, _ in reset() }
        .onChange(of: store.snapshot?.documentIdentity) { _, _ in reset() }
    }

    private func reset() { draft = edge.boneName }
    private func apply() {
        guard draft != edge.boneName else { return }
        store.setEdgeBoneName(edge.id, name: draft)
    }
}
