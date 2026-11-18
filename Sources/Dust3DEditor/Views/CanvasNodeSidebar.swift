import SwiftUI

struct NodesSidebarSelectAll {
    let isEnabled: Bool
    let perform: @MainActor () -> Void
}

/// Search stays separate from the native list's transient selection.
struct CanvasNodeSidebar: View {
    let store: EditorStore
    @Binding var query: String

    var body: some View {
        let renderedQuery = query
        let presentation = store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease)
        let rows =
            presentation?.rows(matching: renderedQuery)
            ?? CanvasNodeSidebarRow.filter(store.snapshot.map(CanvasNodeSidebarRow.rows) ?? [], matching: renderedQuery)
        let displayed = Set(rows.map(\.id))
        let selection = Binding<Set<String>>(
            get: { (store.snapshot?.selectedIDs ?? []).intersection(displayed) },
            set: { ids in
                guard query == renderedQuery, let presentation else { return }
                store.selectCanvasSidebarNodes(ids, matching: renderedQuery, in: presentation)
            })

        VStack(spacing: 0) {
            TextField("Search Nodes", text: $query)
                .textFieldStyle(.roundedBorder)
                .focusedValue(\.editorTextEditing, true)
                .accessibilityLabel("Search Nodes")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            List(selection: selection) {
                ForEach(rows) { row in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            if let part = row.partTitle {
                                Text(part).font(.caption).foregroundStyle(.secondary)
                            }
                            if let status = row.status {
                                Text(status).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: row.status == nil ? "circle.dotted" : "lock")
                    }
                    .accessibilityLabel(row.accessibilityLabel)
                    .tag(row.id)
                    .help(row.id)
                }
            }
            .focusedValue(
                \.editorNodesSidebarSelectAll,
                NodesSidebarSelectAll(isEnabled: presentation != nil && !displayed.isEmpty) {
                    guard query == renderedQuery, let presentation else { return }
                    store.selectAllCanvasSidebarNodes(matching: renderedQuery, in: presentation)
                }
            )
            .listStyle(.sidebar)
            .disabled(presentation == nil)
            .accessibilityLabel("Nodes")
        }
    }
}
