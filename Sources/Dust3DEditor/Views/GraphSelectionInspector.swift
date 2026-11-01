import Dust3DEditorModel
import SwiftUI

/// Explicit graph selection remains distinct from the endpoints used by transform commands.
struct GraphSelectionInspector: View {
    let store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Graph selection").font(.title3)
            Text(
                "\(store.snapshot?.selectedIDs.count ?? 0) nodes · \(store.snapshot?.selectedEdgeIDs.count ?? 0) edges")
            Button("Insert Midpoints on Selected Edges") { store.insertSelectedEdgeMidpoints() }
                .disabled(!store.canInsertEdgeMidpoint)
                .accessibilityLabel("Insert Midpoints on Selected Edges")
            Button("Reverse Selected Edges") { store.reverseExplicitlySelectedEdges() }
                .disabled(!store.canReverseSelectedEdges)
            Menu("Transform Selection") {
                ForEach(SelectionTransform.allCases, id: \.self) { transform in
                    Button(transform.rawValue) { store.transformSelection(transform) }
                        .disabled(!store.canTransformSelection(transform))
                }
            }
            .disabled(!store.canTransform)
            NodeRadiusAdjustmentControls(store: store)
            NodeReductionControls(store: store)
            Button("Delete Graph Selection", role: .destructive) { store.deleteSelection() }
                .disabled(!store.canDeleteGraphSelection)
            Text(
                "Edge commands use the selected edges. Transforms include their endpoints; Exchange X/Z and Reduce use selected nodes. Each edit is one undo step."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
