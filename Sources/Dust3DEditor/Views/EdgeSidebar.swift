import SwiftUI

/// An accessible alternative to pointer picking, including edges whose projection collapses to a point.
struct EdgeSidebar: View {
    let store: EditorStore

    var body: some View {
        let edges = store.snapshot?.edges ?? []
        let titles = Dictionary(uniqueKeysWithValues: (store.snapshot?.nodes ?? []).map { ($0.id, $0.title) })
        if !edges.isEmpty {
            Divider()
            Text("Edges").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(edges) { edge in
                        let title = "\(titles[edge.fromID] ?? edge.fromID) → \(titles[edge.toID] ?? edge.toID)"
                        Button {
                            store.selectEdge(edge.id)
                        } label: {
                            Label(title, systemImage: "line.diagonal")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.snapshot?.selectedEdgeID == edge.id ? .accentColor : .secondary)
                        .accessibilityLabel(
                            "Select edge from \(titles[edge.fromID] ?? edge.fromID) to \(titles[edge.toID] ?? edge.toID)"
                        )
                        .accessibilityValue(store.snapshot?.selectedEdgeID == edge.id ? "Selected" : "Not selected")
                        .help(edge.id)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
            .frame(maxHeight: 180)
            .disabled(store.isWorking)
        }
    }
}
