import Dust3DDocument
import SwiftUI

/// The numeric node draft and its Reset/Apply lifecycle, independent of other inspector commands.
struct NodePropertyEditor: View {
    let store: EditorStore
    let node: DocumentNode
    @Bindable var draft: InspectorNodeDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("X", value: $draft.x, format: .number).accessibilityIdentifier("node-x")
                    .disabled(store.locks.contains(.x))
                TextField("Y", value: $draft.y, format: .number).accessibilityIdentifier("node-y")
                    .disabled(store.locks.contains(.y))
                TextField("Z", value: $draft.z, format: .number).accessibilityIdentifier("node-z")
                    .disabled(store.locks.contains(.z))
                TextField("Radius", value: $draft.radius, format: .number).accessibilityIdentifier("node-radius")
                    .disabled(store.locks.contains(.radius))
            }
            .id(draft.resetID)
            .focusedValue(\.editorTextEditing, true)
            .disabled(store.isWorking || !node.isEditable)
            if !node.isEditable { Label("Locked, hidden or disabled part", systemImage: "lock").font(.caption) }
            HStack {
                Button("Reset") { draft.reset(node.value) }
                Spacer()
                Button("Apply") {
                    store.edit(
                        id: node.id, position: .init(x: draft.x, y: draft.y, z: draft.z), radius: draft.radius)
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(store.isWorking || !node.isEditable)
        }
    }
}
