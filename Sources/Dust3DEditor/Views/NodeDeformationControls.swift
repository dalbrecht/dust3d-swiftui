import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct NodeDeformationControls: View {
    let store: EditorStore
    let node: DocumentNode
    let target: CanvasAdjustmentTarget

    var body: some View {
        DisclosureGroup("Node taper") {
            VStack(alignment: .leading, spacing: 8) {
                Text("These scales multiply the part’s cross-section at this node.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(PartDeformationProperty.allCases, id: \.self) { property in
                    NodeDeformationField(store: store, node: node, property: property, target: target)
                }
            }
            .padding(.top, 4)
        }
    }
}

private struct NodeDeformationField: View {
    let store: EditorStore
    let node: DocumentNode
    let property: PartDeformationProperty
    let target: CanvasAdjustmentTarget
    @State private var draft = ""

    private var title: String { property == .width ? "Node width scale" : "Node thickness scale" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextField(title, text: $draft)
                .accessibilityIdentifier("node-deformation-\(property.rawValue)")
                .focusedValue(\.editorTextEditing, true)
                .onSubmit(apply)
            if node.deformationScale(property) == nil {
                Text("Unsupported source value. Enter a positive scale to replace it.")
                    .font(.caption)
            }
            HStack {
                Button("Reset Draft", action: reset)
                    .accessibilityLabel("Reset \(title.lowercased()) draft")
                Spacer()
                Button("Apply", action: apply)
                    .accessibilityLabel("Apply \(title.lowercased())")
            }
        }
        .onChange(of: node.id, initial: true) { _, _ in reset() }
        .onChange(of: node.deformationScale(property)) { _, _ in reset() }
    }

    private func reset() { draft = node.deformationScale(property).map { String($0) } ?? "" }

    private func apply() {
        store.setNodeDeformationScale(property, draft: draft, nodeID: node.id, target: target)
    }
}
