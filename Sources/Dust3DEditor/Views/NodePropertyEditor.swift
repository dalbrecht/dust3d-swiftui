import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// The numeric node draft and its Reset/Apply lifecycle, independent of other inspector commands.
struct NodePropertyEditor: View {
    let store: EditorStore
    let node: DocumentNode
    let source: InspectorNodeDraftSource?
    @Bindable var draft: InspectorNodeDraft

    var body: some View {
        let actions = source.flatMap { store.nodeInspectorActions(source: $0, draft: draft) }
        let canEditDraft = actions != nil && draft.source == source
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
            .disabled(!canEditDraft)
            if !node.isEditable { Label("Locked, hidden or disabled part", systemImage: "lock").font(.caption) }
            HStack {
                Button("Reset") { actions?.reset() }
                Spacer()
                Button("Apply") { actions?.apply() }
                    .buttonStyle(.borderedProminent)
            }
            .disabled(!canEditDraft)
            if let snapshot = store.snapshot, snapshot.allowsNodeDeformation(for: node.id) {
                NodeDeformationControls(store: store, node: node, target: CanvasAdjustmentTarget(snapshot: snapshot))
                    .id(snapshot.documentIdentity)
                    .disabled(store.isWorking)
            }
        }
    }
}
