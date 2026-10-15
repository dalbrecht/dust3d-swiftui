import Dust3DDocument
import SwiftUI

struct EdgeInspector: View {
    let store: EditorStore
    let edge: DocumentEdge

    var body: some View {
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
            Button("Select Endpoints") { store.select([edge.fromID, edge.toID]) }
                .disabled(store.isWorking)
            Button("Reverse Edge") { store.reverseEdge(edge.id) }
                .disabled(store.isWorking || store.snapshot?.canEditSelectedEdge != true)
            Button("Delete Edge", role: .destructive) { store.deleteSelection() }
                .disabled(store.isWorking || store.snapshot?.canEditSelectedEdge != true)
            if store.snapshot?.canEditSelectedEdge != true {
                Label("Locked or hidden endpoint", systemImage: "lock").font(.caption)
            }
            Text(
                "Reversing or deleting an edge is one undo step. Deleting an edge keeps its nodes and splits disconnected parts."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
