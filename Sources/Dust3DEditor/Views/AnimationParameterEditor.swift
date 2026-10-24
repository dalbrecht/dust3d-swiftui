import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// Add retained parameter text to a captured row; the domain rejects existing attributes atomically.
struct AnimationParameterEditor: View {
    let store: EditorStore
    let target: AnimationEditTarget
    let onCancel: () -> Void
    @State private var name: AnimationNameText
    @State private var value: AnimationNameText
    @State private var isSubmitting = false

    init(
        store: EditorStore, target: AnimationEditTarget,
        name: AnimationNameText = AnimationNameText(""), value: AnimationNameText = AnimationNameText(""),
        onCancel: @escaping () -> Void
    ) {
        self.store = store
        self.target = target
        self.onCancel = onCancel
        _name = State(initialValue: name)
        _value = State(initialValue: value)
    }
    private var isCurrent: Bool { store.snapshot.map { target.isCurrent(in: $0) } ?? false }
    private var canAdd: Bool {
        isCurrent && store.canManageAnimations && !isSubmitting && DocumentAnimationParameter.canEditName(name.value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Parameter").font(.subheadline)
            Text("Name").font(.caption).foregroundStyle(.secondary)
            AnimationNameField(
                text: $name, onSubmit: submit, onCancel: cancel,
                fieldLabel: "New animation parameter name", fieldIdentifier: "animation-parameter-name"
            )
            .frame(height: 28)
            Text("Value").font(.caption).foregroundStyle(.secondary)
            AnimationNameField(
                text: $value, onSubmit: submit, onCancel: cancel,
                fieldLabel: "New animation parameter value", fieldIdentifier: "animation-parameter-value",
                requestsInitialFocus: false
            )
            .frame(height: 28)
            Text("Use an unqualified parameter name. Existing parameters are edited in the inspector.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Stored text only. This does not preview or validate playback.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !isCurrent {
                Text("The document changed. Cancel and select the animation again.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", action: cancel).frame(minHeight: 40).disabled(isSubmitting)
                Spacer()
                Button("Add", action: submit).buttonStyle(.borderedProminent).frame(minHeight: 40).disabled(!canAdd)
            }
        }
        .focusedValue(\.editorTextEditing, true)
        .disabled(store.isWorking || isSubmitting)
    }
    private func cancel() { if !isSubmitting { onCancel() } }
    private func submit() {
        guard canAdd else { return }
        isSubmitting = true
        store.editAnimation(.addParameter(name: name.value, value: value.value), target: target) { accepted in
            isSubmitting = false
            if accepted { onCancel() }
        }
    }
}
