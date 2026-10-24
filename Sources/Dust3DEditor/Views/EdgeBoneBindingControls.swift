import Dust3DDocument
import SwiftUI

struct EdgeBoneBindingControls: View {
    let store: EditorStore
    let edge: DocumentEdge
    @State private var draft = BoneNameIdentity("")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bone assignment").font(.headline)
            ExactBoneNameField(name: $draft, onSubmit: apply, onCancel: reset)
                .frame(minHeight: 40)
                .focusedValue(\.editorTextEditing, true)
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
                    .disabled(edge.hasExactBoneName(draft.rawValue))
            }
            Text("Use the exact bone name. Each applied change is one undo step.")
                .font(.caption).foregroundStyle(.primary)
            Text("Assignments are saved with the document. Rigged preview is not available in this build.")
                .font(.caption).foregroundStyle(.primary)
        }
        .disabled(store.isWorking || store.snapshot?.canEditSelectedEdge != true)
        .onChange(of: edge, initial: true) { _, _ in reset() }
        .onChange(of: store.snapshot?.documentIdentity) { _, _ in reset() }
    }

    private func reset() { draft = BoneNameIdentity(edge.boneName) }
    private func apply() {
        guard !edge.hasExactBoneName(draft.rawValue) else { return }
        store.setEdgeBoneName(edge.id, name: draft.rawValue)
    }
}
