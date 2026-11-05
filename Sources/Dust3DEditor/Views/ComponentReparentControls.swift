import Dust3DEditorModel
import SwiftUI

struct ComponentReparentControls: View {
    let store: EditorStore
    let selection: Set<String>
    @State private var target: ComponentBatchReparentTarget?
    @State private var query = ""
    @State private var parent: ComponentParent?

    private var options: [ComponentParentOption] {
        target?.parentOptions(matching: query) ?? []
    }
    private var isCurrent: Bool {
        guard let target, let snapshot = store.snapshot else { return false }
        return target.isCurrent(in: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let target {
                Text("Move to Parent").font(.headline)
                TextField("Search parent groups", text: $query)
                    .accessibilityIdentifier("component-parent-search")
                    .focusedValue(\.editorTextEditing, true)
                List(selection: $parent) {
                    ForEach(options) { option in
                        Text(option.title).lineLimit(1).tag(option.id)
                            .help(option.id.componentID ?? "Document root container")
                    }
                }
                .frame(height: 120)
                .accessibilityLabel("Eligible component parents")
                .disabled(!isCurrent)
                if !isCurrent {
                    Text("The document or selection changed. Reset the parent chooser.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if options.isEmpty {
                    Text("No matching eligible parents.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Cancel") { self.target = nil }.accessibilityLabel("Cancel component move")
                    Button("Reset") { reset() }.accessibilityLabel("Reset component parent chooser")
                    Spacer()
                    Button("Move") {
                        guard let parent else { return }
                        store.reparentComponents(to: parent, target: target) { succeeded in
                            if succeeded { self.target = nil }
                        }
                    }
                    .disabled(!isCurrent || !options.contains { $0.id == parent })
                    .accessibilityLabel("Move selected components to the chosen parent")
                }
                Text(
                    "Appends selected subtrees in document order. Existing children stay in place. One Undo restores the move."
                )
                .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Move to Parent…") { reset() }
                    .accessibilityLabel("Choose a new parent for the selected components")
                    .accessibilityIdentifier("component-parent-chooser")
            }
        }
        .disabled(store.isWorking)
        .onChange(of: selection) { _, _ in target = nil }
        .onChange(of: query) { _, _ in parent = nil }
    }

    private func reset() {
        guard let snapshot = store.snapshot, snapshot.selectedComponentIDs == selection else { return }
        target = ComponentBatchReparentTarget(snapshot: snapshot)
        query = ""
        parent = nil
    }
}
