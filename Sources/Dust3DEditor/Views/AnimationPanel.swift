import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

enum AnimationNameAction { case rename, duplicate }

/// Stored document animation management. No controls in this view invoke native evaluation.
struct AnimationPanel: View {
    let store: EditorStore
    @State private var nameTarget: AnimationEditTarget?
    @State private var name: AnimationNameText
    @State private var nameAction: AnimationNameAction
    @State private var sourceTitle: String
    @State private var isSubmitting = false

    init(
        store: EditorStore, nameTarget: AnimationEditTarget? = nil,
        name: AnimationNameText = AnimationNameText(""), action: AnimationNameAction = .rename
    ) {
        self.store = store
        _nameTarget = State(initialValue: nameTarget)
        _name = State(initialValue: name)
        _nameAction = State(initialValue: action)
        let sourceID = nameTarget.map { Array($0.animationID.utf8) }
        _sourceTitle = State(
            initialValue: store.animationSnapshot?.list.rows.first { $0.id == sourceID }?.title ?? "animation")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Animations").font(.headline)
                    if let value = store.animationSnapshot, value.list.issue == nil, store.animationQueryIssue == nil {
                        let count = value.list.rows.count
                        Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.refreshAnimations()
                    } label: {
                        Image(systemName: "arrow.clockwise").frame(minWidth: 40, minHeight: 40)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh animation list")
                    .help("Refresh animation details")
                    .disabled(store.isWorking || store.isLoadingAnimations || store.snapshot == nil)
                }
                if let issue = store.animationQueryIssue ?? store.animationSnapshot?.list.issue {
                    Label("Animation details unavailable", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                    Text(issue.localizedDescription).font(.caption).textSelection(.enabled)
                } else if let value = store.animationSnapshot {
                    if value.list.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No stored animations", systemImage: "film")
                            Text("This document has no animation records.").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                    } else {
                        animationList(value)
                        if nameTarget == nil { actions(value) }
                        if let row = value.list.selectedRow {
                            if nameTarget == nil { details(row.source) }
                        } else if nameTarget == nil {
                            Text("Select an animation to inspect its details.").font(.caption).foregroundStyle(
                                .secondary)
                        }
                    }
                } else if store.isLoadingAnimations || store.isWorking {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading animation details…")
                    }.font(.caption)
                } else {
                    Text("Open a document or refresh to inspect stored animations.").font(.caption)
                }
                if nameTarget != nil { nameEditor }
                Divider()
                Text("Changes are included when you save. Playback is not available yet.")
                    .font(.caption).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .focusedValue(\.editorAnimationFocus, true)
        .task(id: store.snapshot?.documentIdentity) { refreshIfNeeded() }
        .onChange(of: store.snapshot?.documentRevision) { _, _ in refreshIfNeeded() }
    }

    private func animationList(_ value: EditorAnimationSnapshot) -> some View {
        List(
            selection: Binding<[UInt8]?>(
                get: { store.animationSnapshot?.list.selectedID },
                set: { identity in
                    let id = store.animationSnapshot?.list.rows.first { $0.id == identity }?.source.id
                    store.selectAnimation(id)
                })
        ) {
            ForEach(value.list.rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: "film").foregroundStyle(.secondary).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).lineLimit(1)
                        Text(row.typeLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .tag(row.id)
                .help("\(row.title) · \(row.source.id)")
                .accessibilityLabel("Animation \(row.title)")
            }
        }
        .listStyle(.inset)
        .frame(height: 180)
        .accessibilityLabel("Stored animations")
        .disabled(store.isWorking || nameTarget != nil)
        .onDeleteCommand { deleteSelection() }
    }

    private func actions(_ value: EditorAnimationSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    beginNameAction(.rename, value: value)
                } label: {
                    Text("Rename").fixedSize().frame(maxWidth: .infinity, minHeight: 40)
                }
                Button {
                    beginNameAction(.duplicate, value: value)
                } label: {
                    Text("Duplicate").fixedSize().frame(maxWidth: .infinity, minHeight: 40)
                }
            }
            Button(role: .destructive) {
                deleteSelection()
            } label: {
                Label("Delete Animation", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 40)
            }
            .accessibilityLabel("Delete animation")
            .help("Delete selected animation; Undo restores it")
        }
        .buttonStyle(.bordered)
        .disabled(!store.canManageAnimations || value.list.selectedRow == nil)
    }

    private func details(_ record: DocumentAnimation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stored type").font(.caption).foregroundStyle(.secondary)
            Text(record.type ?? "Unspecified type").textSelection(.enabled)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if !record.parameters.isEmpty {
                Divider()
                Text("Parameters").font(.subheadline)
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(record.parameters.indices, id: \.self) { index in
                        let parameter = record.parameters[index]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(parameter.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(parameter.value).monospacedDigit().textSelection(.enabled).lineLimit(3)
                        }
                    }
                }
            }
        }
    }

    private var targetIsCurrent: Bool {
        guard let nameTarget, let snapshot = store.snapshot else { return false }
        return nameTarget.isCurrent(in: snapshot)
    }
    private var nameEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(nameAction == .rename ? "Rename" : "Duplicate") \(sourceTitle)").font(.subheadline).lineLimit(2)
            AnimationNameField(text: $name, onSubmit: submitName, onCancel: cancelName)
                .frame(height: 28)
                .focusedValue(\.editorTextEditing, true)
                .disabled(store.isWorking || isSubmitting)
            if !targetIsCurrent {
                Text("The document changed. Cancel and select the animation again.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", action: cancelName).frame(minHeight: 40).disabled(isSubmitting)
                Spacer()
                Button(nameAction == .rename ? "Apply Name" : "Duplicate", action: submitName)
                    .buttonStyle(.borderedProminent).frame(minHeight: 40)
                    .disabled(!targetIsCurrent || !store.canManageAnimations || isSubmitting)
            }
        }
    }
    private func beginNameAction(_ action: AnimationNameAction, value: EditorAnimationSnapshot) {
        guard store.canManageAnimations, let row = value.list.selectedRow else { return }
        do {
            nameTarget = try AnimationEditTarget(snapshot: value, animationID: row.source.id)
            sourceTitle = row.title
            nameAction = action
            name = AnimationNameText(action == .rename ? (row.source.name ?? "") : row.title + " copy")
        } catch { store.errorMessage = error.localizedDescription }
    }
    private func submitName() {
        guard let nameTarget, targetIsCurrent, store.canManageAnimations, !isSubmitting else { return }
        isSubmitting = true
        let completion: @MainActor (Bool) -> Void = { accepted in
            isSubmitting = false
            if accepted { self.nameTarget = nil }
        }
        switch nameAction {
        case .rename: store.editAnimation(.rename(name.value), target: nameTarget, completion: completion)
        case .duplicate: store.duplicateAnimation(target: nameTarget, name: name.value, completion: completion)
        }
    }
    private func cancelName() { if !isSubmitting { nameTarget = nil } }
    private func deleteSelection() {
        guard nameTarget == nil, store.canManageAnimations, let value = store.animationSnapshot,
            let row = value.list.selectedRow
        else { return }
        do {
            store.editAnimation(.delete, target: try AnimationEditTarget(snapshot: value, animationID: row.source.id))
        } catch { store.errorMessage = error.localizedDescription }
    }
    private func refreshIfNeeded() {
        if store.animationSnapshot == nil && !store.isLoadingAnimations { store.refreshAnimations() }
    }
}
