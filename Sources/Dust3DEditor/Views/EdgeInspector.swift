import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct EdgeInspector: View {
    let store: EditorStore
    let edge: DocumentEdge

    var body: some View {
        let context = store.snapshot.map { GraphInspectorActionContext(snapshot: $0) }
        let select = context?.target(for: .selectEndpoints(edgeID: edge.id))
        let boneSelect = context?.target(for: .selectBoneEdges(edgeID: edge.id))
        let midpoint = context?.target(for: .insertMidpoint(edgeID: edge.id))
        let reverse = context?.target(for: .reverseEdge(id: edge.id))
        let repairDirections = context?.target(for: .repairEdgeDirections(edgeID: edge.id))
        let delete = context?.target(for: .disconnectEdge(id: edge.id))
        let nodes = store.snapshot?.nodes ?? []
        let from = nodes.first { $0.id == edge.fromID }?.title ?? edge.fromID
        let to = nodes.first { $0.id == edge.toID }?.title ?? edge.toID
        VStack(alignment: .leading, spacing: 16) {
            Text("Edge inspector").font(.title3)
            Text(edge.id).font(.caption).textSelection(.enabled)
                .focusedValue(\.editorTextEditing, true)
            Text("From: \(from)")
            Text("To: \(to)")
            Text("Direction: \(from) → \(to)").font(.caption)
            NodeRadiusAdjustmentControls(store: store)
            CanvasRotationControls(store: store)
            CanvasPrecisionControls(store: store)
            GraphColorizeControls(store: store)
            Button("Select Whole Part", action: store.wholePartSelectionAction(.edge(edge.id)))
                .disabled(!store.canSelectWholePart(.edge(edge.id)))
            Button("Select Endpoints", action: store.inspectorAction(select))
                .disabled(!store.canPerformInspectorAction(select))
            Button("Select Bone Edges", action: store.inspectorAction(boneSelect))
                .disabled(!store.canPerformInspectorAction(boneSelect))
                .help("Select visible, editable edges with this exact stored bone assignment.")
            Button("Insert Midpoint", action: store.inspectorAction(midpoint))
                .disabled(!store.canPerformInspectorAction(midpoint))
                .accessibilityLabel("Insert Midpoint")
            Button("Reverse Edge", action: store.inspectorAction(reverse))
                .disabled(!store.canPerformInspectorAction(reverse))
            if repairDirections?.changesDocument == true {
                Button("Repair Edge Directions", action: store.inspectorAction(repairDirections))
                    .disabled(!store.canPerformInspectorAction(repairDirections))
                    .help("Align the directions in this part’s open chain in one undo step.")
            }
            Button("Delete Edge", role: .destructive, action: store.inspectorAction(delete))
                .disabled(!store.canPerformInspectorAction(delete))
            if !store.canPerformInspectorAction(reverse) {
                Label(
                    store.snapshot?.canEditSelectedEdge == false
                        ? "Locked, hidden or disabled endpoint" : "Edge editing unavailable", systemImage: "lock"
                ).font(.caption)
                    .help("Editing requires the current edge and editable supported endpoints.")
            }
            Text(
                "Inserting a midpoint, reversing or deleting an edge is one undo step. Deleting an edge keeps its nodes and splits disconnected parts."
            )
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            EdgeBoneBindingControls(store: store, edge: edge)
        }
    }
}
