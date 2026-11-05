import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct NodeInspector: View {
    let store: EditorStore
    @State private var draft: InspectorNodeDraft

    init(store: EditorStore, draft: InspectorNodeDraft = InspectorNodeDraft()) {
        self.store = store
        _draft = State(initialValue: draft)
    }

    var body: some View { ScrollView { content } }

    private var content: some View {
        return VStack(alignment: .leading, spacing: 16) {
            Text("Selection inspector").font(.headline)
            AddModeControls(store: store)
            OriginControls(store: store)
            RigSettingsControls(store: store)
            NodeClipboardMenu(store: store)
            if let snapshot = store.snapshot, !snapshot.selectedComponentIDs.isEmpty {
                ComponentDeletionButton(store: store, target: ComponentDeletionTarget(snapshot: snapshot))
                ComponentUngroupButton(store: store, target: ComponentUngroupTarget(snapshot: snapshot))
                ComponentReparentControls(store: store, selection: snapshot.selectedComponentIDs)
                ComponentBatchOrderMenu(store: store, snapshot: snapshot)
            }
            ComponentMeshSelectionControls(store: store)
            if let component = store.snapshot?.selectedComponent {
                ComponentInspector(store: store, component: component)
            } else if let part = store.snapshot?.selectedPart {
                PartInspector(store: store, part: part)
            } else if store.snapshot?.selectedEdgeIDs.isEmpty == false
                && (store.snapshot?.selectedIDs.isEmpty == false || (store.snapshot?.selectedEdgeIDs.count ?? 0) > 1)
            {
                GraphSelectionInspector(store: store)
            } else if let edge = store.snapshot?.selectedEdge {
                EdgeInspector(store: store, edge: edge)
            } else if (store.snapshot?.selectedIDs.count ?? 0) > 1 {
                GroupInspector(store: store)
            } else if let node = store.snapshot?.selectedNode {
                let targets = store.snapshot?.connectionTargets ?? []
                let editableEdges = Set(store.snapshot?.editableEdges.map(\.id) ?? [])
                Text(node.title).font(.title3)
                Button("Select Whole Part", action: store.wholePartSelectionAction(.node(node.id)))
                    .disabled(!store.canSelectWholePart(.node(node.id)))
                SelectableNodeIdentifier(value: node.id)
                    .focusedValue(\.editorTextEditing, true)
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
                NodeRadiusAdjustmentControls(store: store)
                NodeReductionControls(store: store)
                SelectionTransformMenu(store: store)
                DescendantRotationMenu(store: store)
                Divider()
                Menu("Connect to…") {
                    ForEach(targets) { target in
                        Button(target.title) { store.connect(to: target.id) }
                    }
                }
                .disabled(store.isWorking || !node.isEditable || targets.isEmpty)
                .help("Joining parts uses the selected node's part settings. Undo restores both parts.")
                ForEach((store.snapshot?.edges ?? []).filter { $0.fromID == node.id || $0.toID == node.id }) { edge in
                    let from = store.snapshot?.nodes.first { $0.id == edge.fromID }?.title ?? edge.fromID
                    let to = store.snapshot?.nodes.first { $0.id == edge.toID }?.title ?? edge.toID
                    Menu("\(from) → \(to)") {
                        Button("Reverse Direction") { store.reverseEdge(edge.id) }
                        Button("Disconnect") { store.deleteEdge(edge.id) }
                    }
                    .accessibilityLabel("Edge from \(from) to \(to)")
                    .disabled(store.isWorking || !editableEdges.contains(edge.id))
                }
                Button("Delete Node", role: .destructive) { store.deleteNode() }
                    .disabled(store.isWorking || !node.isEditable)
                Text("Coordinates use document units. Dragging moves in the selected canvas plane.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Select a node, edge, part or component.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .onChange(of: store.snapshot?.selectedNode, initial: true) { _, node in
            if let node { draft.reset(node.value) }
        }
        .onChange(of: store.locks) { previous, current in
            guard let node = store.snapshot?.selectedNode else { return }
            if current.contains(.x) && !previous.contains(.x) { draft.x = node.value.position.x }
            if current.contains(.y) && !previous.contains(.y) { draft.y = node.value.position.y }
            if current.contains(.z) && !previous.contains(.z) { draft.z = node.value.position.z }
            if current.contains(.radius) && !previous.contains(.radius) { draft.radius = node.value.radius }
        }
    }

}

private struct GroupInspector: View {
    let store: EditorStore

    var body: some View {
        let selected = store.snapshot?.selectedNodes ?? []
        let editable = selected.filter(\.isEditable).count
        VStack(alignment: .leading, spacing: 12) {
            Text("\(selected.count) selected").font(.title3)
            Text("\(editable) editable · \(selected.count - editable) read-only").font(.caption)
            SelectionTransformControls(store: store)
            NodeRadiusAdjustmentControls(store: store)
            NodeReductionControls(store: store)
            SelectionTransformMenu(store: store)
            Button("Reverse Selected Edges") { store.reverseSelectedEdges() }
                .disabled(store.snapshot?.reversibleEdges.isEmpty != false)
            Divider()
            Button("Delete Selected Nodes", role: .destructive) { store.deleteSelection() }
            Text("Read-only nodes stay fixed. Each move or deletion is one undo step.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(store.isWorking || editable == 0)
    }
}

private struct SelectionTransformMenu: View {
    let store: EditorStore
    var body: some View {
        Menu("Transform Selected Nodes") {
            ForEach(SelectionTransform.allCases, id: \.self) { transform in
                Button(transform.rawValue) { store.transformSelection(transform) }
                    .disabled(!store.canTransformSelection(transform))
            }
        }
        .disabled(!store.canTransform)
    }
}
