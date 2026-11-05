import SwiftUI

/// Inspector entry point shares availability and routing with the native Canvas menu.
struct NodeReductionControls: View {
    let store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Reduce Selected Nodes") { store.reduceSelectedNodes() }
                .disabled(!store.canReduceSelectedNodes)
                .accessibilityLabel("Reduce Selected Nodes")
            Text("Removes selected nodes with two connections and joins their neighbors in one undo step.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
