import Dust3DEditorModel
import SwiftUI

/// Create stored intent only; no catalog, timing defaults or generator support are inferred.
struct AnimationCreationEditor: View {
    let store: EditorStore
    let target: AnimationCreationTarget
    let onCancel: () -> Void
    @State private var name: AnimationNameText
    @State private var type: AnimationNameText
    @State private var isSubmitting = false

    init(
        store: EditorStore, target: AnimationCreationTarget,
        name: AnimationNameText = AnimationNameText(""), type: AnimationNameText = AnimationNameText(""),
        onCancel: @escaping () -> Void
    ) {
        self.store = store
        self.target = target
        self.onCancel = onCancel
        _name = State(initialValue: name)
        _type = State(initialValue: type)
    }
    private var isCurrent: Bool { store.snapshot.map { target.isCurrent(in: $0) } ?? false }
    private var canCreate: Bool { isCurrent && store.canManageAnimations && !isSubmitting && !type.value.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Stored Animation").font(.subheadline)
            Text("Name (optional)").font(.caption).foregroundStyle(.secondary)
            AnimationNameField(
                text: $name, onSubmit: submit, onCancel: cancel,
                fieldLabel: "New animation name", fieldIdentifier: "animation-create-name"
            )
            .frame(height: 44)
            Text("Type").font(.caption).foregroundStyle(.secondary)
            AnimationNameField(
                text: $type, onSubmit: submit, onCancel: cancel,
                fieldLabel: "New animation type", fieldIdentifier: "animation-create-type", requestsInitialFocus: false
            )
            .frame(height: 44)
            Text("Enter the stored animation type. Preview and playback support are not checked.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !isCurrent {
                Text("The document changed. Cancel and start a new animation again.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(action: cancel) {
                    Text("Cancel").frame(minWidth: 40, minHeight: 40)
                }.disabled(isSubmitting)
                Spacer()
                Button(action: submit) {
                    Text("Create").frame(minWidth: 40, minHeight: 40)
                }.buttonStyle(.borderedProminent).disabled(!canCreate)
            }
        }
        .focusedValue(\.editorTextEditing, true)
        .disabled(store.isWorking || isSubmitting)
    }
    private func cancel() { if !isSubmitting { onCancel() } }
    private func submit() {
        guard canCreate else { return }
        isSubmitting = true
        store.createAnimation(name: name.value, type: type.value, target: target) { accepted in
            isSubmitting = false
            if accepted { onCancel() }
        }
    }
}
