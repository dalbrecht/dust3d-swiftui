import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct EdgeBoneBindingControls: View {
    let store: EditorStore
    let edge: DocumentEdge

    var body: some View {
        if let snapshot = store.snapshot {
            EdgeBoneAssignmentEditor(
                store: store, target: EdgeBoneAssignmentTarget(snapshot: snapshot, edgeIDs: [edge.id]))
        }
    }
}

/// Explicit selected edges only; selected nodes never infer additional assignments.
struct EdgeBoneSelectionControls: View {
    let store: EditorStore
    var body: some View {
        if let snapshot = store.snapshot, !snapshot.selectedEdgeIDs.isEmpty {
            EdgeBoneAssignmentEditor(store: store, target: EdgeBoneAssignmentTarget(snapshot: snapshot))
        }
    }
}

private struct EdgeBoneAssignmentEditor: View {
    let store: EditorStore
    let target: EdgeBoneAssignmentTarget
    @State private var draft: EdgeBoneNameDraft

    init(store: EditorStore, target: EdgeBoneAssignmentTarget) {
        self.store = store
        self.target = target
        _draft = State(initialValue: EdgeBoneNameDraft(target: target))
    }

    private var editable: Bool {
        guard let snapshot = store.snapshot else { return false }
        return target.isCurrent(in: snapshot)
    }
    private var mixed: Bool { target.selectedCount > 1 && target.commonName == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(target.selectedCount > 1 ? "Bone assignments" : "Bone assignment").font(.headline)
            ExactBoneNameField(
                name: Binding(get: { draft.value }, set: { draft.edit($0) }),
                placeholder: mixed ? "Multiple bone names" : "Unassigned", onSubmit: apply, onCancel: reset
            )
            .frame(minHeight: 40)
            .focusedValue(\.editorTextEditing, true)
            HStack {
                Button(action: reset) { Text("Reset Draft").frame(minHeight: 32) }
                    .accessibilityLabel("Reset bone name draft")
                Spacer()
                Button(action: store.assignBoneNameAction("", target: draft.target)) {
                    Text(target.selectedCount > 1 ? "Clear All" : "Clear").frame(minHeight: 32)
                }
                .accessibilityLabel(
                    target.selectedCount > 1 ? "Clear selected bone assignments" : "Clear bone assignment"
                )
                .disabled(!store.canAssignBoneName("", target: draft.target))
                Button(action: apply) { Text("Apply").frame(minHeight: 32) }
                    .accessibilityLabel(
                        target.selectedCount > 1 ? "Apply selected bone assignments" : "Apply bone assignment"
                    )
                    .disabled(!draft.canSubmit || !store.canAssignBoneName(draft.value.rawValue, target: draft.target))
            }
            if mixed {
                Text(
                    "Selected edges have different bone names. Apply replaces them with one exact name; Clear All removes their assignments."
                )
                .font(.caption).foregroundStyle(.primary)
            }
            Text("Use the exact bone name. Each applied change is one undo step.")
                .font(.caption).foregroundStyle(.primary)
            Text("Assignments are saved with the document. Rigged preview is not available in this build.")
                .font(.caption).foregroundStyle(.primary)
        }
        .disabled(store.isWorking || !editable)
        // Keep the native field identity and caret during unrelated publications.
        // A changed source/selection epoch resets the draft without replacing the field.
        .onChange(of: target, initial: true) { _, value in draft = EdgeBoneNameDraft(target: value) }
    }

    private func reset() { draft.reset() }
    private func apply() {
        guard draft.canSubmit else { return }
        store.assignBoneNameAction(draft.value.rawValue, target: draft.target)()
    }
}
