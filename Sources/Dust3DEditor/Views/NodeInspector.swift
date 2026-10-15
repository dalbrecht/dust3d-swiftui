import Dust3DDocument
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
            if let node = store.snapshot?.selectedNode {
                Text(node.title).font(.title3)
                Text(node.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Form {
                    TextField("X", value: $x, format: .number).accessibilityIdentifier("node-x")
                    TextField("Y", value: $y, format: .number).accessibilityIdentifier("node-y")
                    TextField("Z", value: $z, format: .number).accessibilityIdentifier("node-z")
                    TextField("Radius", value: $radius, format: .number).accessibilityIdentifier("node-radius")
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
                Divider()
                Menu("Connect to…") {
                    ForEach(
                        (store.snapshot?.nodes ?? []).filter {
                            $0.id != node.id && $0.partID == node.partID && $0.isEditable
                        }
                    ) { target in
                        Button(target.title) { store.connect(to: target.id) }
                    }
                }
                .disabled(store.isWorking || !node.isEditable)
                ForEach((store.snapshot?.edges ?? []).filter { $0.fromID == node.id || $0.toID == node.id }) { edge in
                    Button(
                        "Disconnect \(store.snapshot?.nodes.first(where: { $0.id == (edge.fromID == node.id ? edge.toID : edge.fromID) })?.title ?? "node")"
                    ) { store.deleteEdge(edge.id) }
                    .disabled(store.isWorking || !node.isEditable)
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
    }

    private func reset(_ node: EditableNode) {
        x = node.position.x
        y = node.position.y
        z = node.position.z
        radius = node.radius
    }
}
