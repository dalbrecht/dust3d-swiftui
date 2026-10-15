import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct NodeInspector: View {
    let store: EditorStore
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var z = 0.0
    @State private var radius = 0.0

    var body: some View { ScrollView { content } }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Node inspector").font(.headline)
            if (store.snapshot?.selectedIDs.count ?? 0) > 1 {
                GroupInspector(store: store)
            } else if let node = store.snapshot?.selectedNode {
                let targets = store.snapshot?.connectionTargets ?? []
                let editableEdges = Set(store.snapshot?.editableEdges.map(\.id) ?? [])
                Text(node.title).font(.title3)
                Text(node.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Form {
                    TextField("X", value: $x, format: .number).accessibilityIdentifier("node-x")
                        .disabled(store.locks.contains(.x))
                    TextField("Y", value: $y, format: .number).accessibilityIdentifier("node-y")
                        .disabled(store.locks.contains(.y))
                    TextField("Z", value: $z, format: .number).accessibilityIdentifier("node-z")
                        .disabled(store.locks.contains(.z))
                    TextField("Radius", value: $radius, format: .number).accessibilityIdentifier("node-radius")
                        .disabled(store.locks.contains(.radius))
                }
                .disabled(store.isWorking || !node.isEditable)
                if !node.isEditable { Label("Locked or hidden part", systemImage: "lock").font(.caption) }
                HStack {
                    Button("Reset") { reset(node.value) }
                    Spacer()
                    Button("Apply") { store.edit(id: node.id, position: .init(x: x, y: y, z: z), radius: radius) }
                        .buttonStyle(.borderedProminent)
                }
                .disabled(store.isWorking || !node.isEditable)
                SelectionTransformMenu(store: store)
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
                Text("Select a node in the list or canvas.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .onChange(of: store.snapshot?.selectedNode, initial: true) { _, node in
            if let node { reset(node.value) }
        }
        .onChange(of: store.locks) { previous, current in
            guard let node = store.snapshot?.selectedNode else { return }
            if current.contains(.x) && !previous.contains(.x) { x = node.value.position.x }
            if current.contains(.y) && !previous.contains(.y) { y = node.value.position.y }
            if current.contains(.z) && !previous.contains(.z) { z = node.value.position.z }
            if current.contains(.radius) && !previous.contains(.radius) { radius = node.value.radius }
        }
    }

    private func reset(_ node: EditableNode) {
        x = node.position.x
        y = node.position.y
        z = node.position.z
        radius = node.radius
    }
}

private struct GroupInspector: View {
    let store: EditorStore
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var z = 0.0
    @State private var positionFactor = 1.0
    @State private var radiusFactor = 1.0

    var body: some View {
        let selected = store.snapshot?.selectedNodes ?? []
        let editable = selected.filter(\.isEditable).count
        VStack(alignment: .leading, spacing: 12) {
            Text("\(selected.count) selected").font(.title3)
            Text("\(editable) editable · \(selected.count - editable) read-only").font(.caption)
            Text("Move by document units").font(.headline)
            Form {
                TextField("Δ X", value: $x, format: .number).disabled(store.locks.contains(.x))
                TextField("Δ Y", value: $y, format: .number).disabled(store.locks.contains(.y))
                TextField("Δ Z", value: $z, format: .number).disabled(store.locks.contains(.z))
            }
            Button("Move Selection") { store.moveSelection(by: .init(x: x, y: y, z: z)) }
                .buttonStyle(.borderedProminent)
            Divider()
            Text("Scale around selection center").font(.headline)
            Form {
                TextField("Positions ×", value: $positionFactor, format: .number)
                    .disabled(store.locks.isSuperset(of: [.x, .y, .z]))
                TextField("Radii ×", value: $radiusFactor, format: .number)
                    .disabled(store.locks.contains(.radius))
            }
            Button("Scale Selection") {
                store.scaleSelection(positionFactor: positionFactor, radiusFactor: radiusFactor)
            }
            Text("Positive factors. 1 keeps the current size. The center uses editable nodes only.")
                .font(.caption).foregroundStyle(.secondary)
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
            }
        }
        .disabled(!store.canTransform)
    }
}
