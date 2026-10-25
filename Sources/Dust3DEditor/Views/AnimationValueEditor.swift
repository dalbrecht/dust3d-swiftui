import SwiftUI

/// Edit retained metadata without interpreting durations, types or generator parameters.
struct AnimationValueEditor: View {
    let store: EditorStore
    let draft: AnimationValueDraft
    let onCancel: () -> Void
    @State private var text: AnimationNameText
    @State private var isSubmitting = false

    init(store: EditorStore, draft: AnimationValueDraft, onCancel: @escaping () -> Void) {
        self.store = store
        self.draft = draft
        self.onCancel = onCancel
        _text = State(initialValue: AnimationNameText(draft.originalValue))
    }
    private var isCurrent: Bool { store.snapshot.map { draft.target.isCurrent(in: $0) } ?? false }
    private var canApply: Bool { isCurrent && store.canManageAnimations && !isSubmitting && draft.field.isEditable }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit \(draft.field.title)").font(.subheadline).lineLimit(2)
            AnimationNameField(
                text: $text, onSubmit: { submit(removing: false) }, onCancel: cancel,
                fieldLabel: "Animation \(draft.field.title)", fieldIdentifier: "animation-stored-value"
            )
            .frame(height: 44)
            .focusedValue(\.editorTextEditing, true)
            .disabled(store.isWorking || isSubmitting)
            Text("Stored text only. This does not preview or validate playback.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !isCurrent {
                Text("The document changed. Cancel and select the animation again.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(action: cancel) {
                    Text("Cancel").frame(minWidth: 40, minHeight: 40)
                }.disabled(isSubmitting)
                Spacer()
                Button(action: { submit(removing: false) }) {
                    Text("Apply").frame(minWidth: 40, minHeight: 40)
                }
                .buttonStyle(.borderedProminent).disabled(!canApply)
            }
            if draft.field.removal != nil {
                Button(role: .destructive) {
                    submit(removing: true)
                } label: {
                    Label("Remove Parameter", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered).disabled(!canApply)
                Text("An empty value keeps the parameter. Remove deletes its stored attribute.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func cancel() { if !isSubmitting { onCancel() } }
    private func submit(removing: Bool) {
        guard canApply else { return }
        let edit = removing ? draft.field.removal : draft.field.edit(value: text.value)
        guard let edit else { return }
        isSubmitting = true
        store.editAnimation(edit, target: draft.target) { accepted in
            isSubmitting = false
            if accepted { onCancel() }
        }
    }
}
