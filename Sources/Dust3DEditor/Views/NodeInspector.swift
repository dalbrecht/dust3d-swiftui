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
        let actionContext = store.snapshot.map { GraphInspectorActionContext(snapshot: $0) }
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
                if snapshot.selectedComponentIDs.count > 1 {
                    let colorTarget = ComponentMeshSelectionTarget(snapshot: snapshot)
                    ComponentBatchPartStateMenu(store: store, target: colorTarget)
                    ComponentBatchColorControls(store: store, target: colorTarget)
                        .id(colorTarget)
                }
            }
            if let snapshot = store.snapshot {
                let target = GraphPartShapeTarget(snapshot: snapshot)
                if let part = target.part {
                    DisclosureGroup("Owning Part Shape") {
                        Text(part.title).font(.caption).foregroundStyle(.secondary)
                        PartModifierControls(part: part, properties: GraphPartShapeTarget.properties) {
                            property, value in
                            store.setGraphPartShape(property, value: value, target: target)
                        }
                        .disabled(!store.canEditGraphPartShape(target))
                    }
                    .help("Change subdivision, chamfer or rounded ends on \(part.title). Each edit is one Undo step.")
                }
            }
            ComponentMeshSelectionControls(store: store)
            if store.snapshot?.selectedComponentIDs.isEmpty == false {
                ComponentPartRoleControls(store: store)
                ComponentWrappingSelectionControls(store: store)
            }
            if let component = store.snapshot?.selectedComponent {
                ComponentInspector(store: store, component: component)
            } else if let part = store.snapshot?.inspectedPart {
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
                let targets = (store.snapshot?.connectionTargets ?? []).filter {
                    store.canPerformInspectorAction(actionContext?.target(for: .connect(from: node.id, to: $0.id)))
                }
                Text(node.title).font(.title3)
                Button("Select Whole Part", action: store.wholePartSelectionAction(.node(node.id)))
                    .disabled(!store.canSelectWholePart(.node(node.id)))
                SelectableNodeIdentifier(value: node.id)
                    .focusedValue(\.editorTextEditing, true)
                NodePropertyEditor(store: store, node: node, draft: draft)
                NodeRadiusAdjustmentControls(store: store)
                CanvasRotationControls(store: store)
                EndpointBendControls(store: store, endpointID: node.id)

                CanvasPrecisionControls(store: store)
                GraphColorizeControls(store: store)
                NodeReductionControls(store: store)
                SelectionTransformMenu(store: store)
                DescendantRotationMenu(store: store)
                Divider()
                Menu("Connect to…") {
                    ForEach(targets) { target in
                        let intent = actionContext?.target(for: .connect(from: node.id, to: target.id))
                        Button(target.title, action: store.inspectorAction(intent))
                            .disabled(!store.canPerformInspectorAction(intent))
                    }
                }
                .disabled(store.isWorking || !node.isEditable || targets.isEmpty)
                .help("Joining parts uses the selected node's part settings. Undo restores both parts.")
                ForEach((store.snapshot?.edges ?? []).filter { $0.fromID == node.id || $0.toID == node.id }) { edge in
                    let from = store.snapshot?.nodes.first { $0.id == edge.fromID }?.title ?? edge.fromID
                    let to = store.snapshot?.nodes.first { $0.id == edge.toID }?.title ?? edge.toID
                    let reverse = actionContext?.target(for: .reverseEdge(id: edge.id))
                    let disconnect = actionContext?.target(for: .disconnectEdge(id: edge.id))
                    Menu("\(from) → \(to)") {
                        Button("Reverse Direction", action: store.inspectorAction(reverse))
                            .disabled(!store.canPerformInspectorAction(reverse))
                        Button("Disconnect", action: store.inspectorAction(disconnect))
                            .disabled(!store.canPerformInspectorAction(disconnect))
                    }
                    .accessibilityLabel("Edge from \(from) to \(to)")
                    .disabled(!store.canPerformInspectorAction(reverse) && !store.canPerformInspectorAction(disconnect))
                }
                let delete = actionContext?.target(for: .deleteNode(id: node.id))
                Button("Delete Node", role: .destructive, action: store.inspectorAction(delete))
                    .disabled(!store.canPerformInspectorAction(delete))
                Text("Coordinates use document units. Dragging moves in the selected canvas plane.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Select a node, edge, part or component.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .onChange(of: InspectorNodeDraftSource(store.snapshot), initial: true) { _, source in
            if let source { draft.reset(source.geometry) }
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
            CanvasRotationControls(store: store)
            CanvasPrecisionControls(store: store)
            GraphColorizeControls(store: store)
            NodeReductionControls(store: store)
            NodeConnectionControls(store: store)
            SelectionTransformMenu(store: store)
            Button("Reverse Edges Between Selected Nodes") { store.reverseSelectedEdges() }
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
