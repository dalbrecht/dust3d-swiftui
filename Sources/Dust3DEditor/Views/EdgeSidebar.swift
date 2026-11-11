import AppKit
import Dust3DEditorModel
import SwiftUI

struct EdgeSidebarRow: Identifiable {
    let id: String
    let from: String
    let to: String
    private let searchText: String

    static func rows(in snapshot: EditorSnapshot) -> [Self] {
        let titles = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { (Data($0.id.utf8), $0.title) })
        return snapshot.edges.map { edge in
            let from = titles[Data(edge.fromID.utf8)] ?? edge.fromID
            let to = titles[Data(edge.toID.utf8)] ?? edge.toID
            return Self(
                id: edge.id, from: from, to: to,
                searchText: "\(from) \(to) \(edge.id) \(edge.fromID) \(edge.toID) \(edge.boneName)")
        }
    }

    static func filter(_ rows: [Self], matching query: String) -> [Self] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return rows }
        return rows.filter { row in
            terms.allSatisfy { row.searchText.localizedStandardContains(String($0)) }
        }
    }
}

/// An accessible alternative to pointer picking, including edges whose projection collapses to a point.
struct EdgeSidebar: View {
    let store: EditorStore
    @State private var query = ""
    @State private var filterRevision = UUID()

    var body: some View {
        let rows = EdgeSidebarRow.filter(store.snapshot.map(EdgeSidebarRow.rows) ?? [], matching: query)
        let renderedRevision = filterRevision
        let admitsFilter: @MainActor () -> Bool = { filterRevision == renderedRevision }
        let partContext = store.snapshot.map { PartGraphSelectionContext(snapshot: $0) }
        if let selectAll = store.edgeSidebarSelectAllTarget(
            displayedIDs: Set(rows.map(\.id)), admitsFilter: admitsFilter)
        {
            Divider()
            Text("Edges").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            TextField(
                "Search Edges",
                text: Binding(
                    get: { query },
                    set: {
                        guard $0 != query else { return }
                        query = $0
                        filterRevision = UUID()
                    })
            )
            .textFieldStyle(.roundedBorder)
            .focusedValue(\.editorTextEditing, true)
            .padding(.horizontal, 12)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    if rows.isEmpty {
                        Text("No matching edges")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { edge in
                        let action = store.edgeSidebarSelectionAction(edge.id, context: partContext)
                        let selectEdge: @MainActor (GraphSelectionMode) -> Void = { mode in
                            guard admitsFilter() else { return }
                            action(mode)
                        }
                        let selectWholePart = store.wholePartSelectionAction(.edge(edge.id))
                        let revealOwningComponent = store.revealOwningComponentAction(
                            .edge(edge.id), context: partContext)
                        let title = "\(edge.from) → \(edge.to)"
                        let isSelected = store.snapshot?.selectedEdgeIDs.contains(edge.id) == true
                        Button {
                            let flags = NSApp.currentEvent?.modifierFlags ?? []
                            if flags.contains(.command) {
                                selectEdge(.toggle)
                            } else if flags.contains(.shift) {
                                selectEdge(.add)
                            } else {
                                selectEdge(.replace)
                            }
                        } label: {
                            Label(
                                title,
                                systemImage: isSelected
                                    ? "checkmark.circle.fill" : "line.diagonal"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(isSelected ? .accentColor : .secondary)
                        .accessibilityLabel(
                            "Select edge from \(edge.from) to \(edge.to)"
                        )
                        .accessibilityAddTraits(
                            isSelected ? .isSelected : []
                        )
                        .accessibilityValue(
                            isSelected ? "Selected" : "Not selected"
                        )
                        .accessibilityAction(named: Text("Add edge to selection")) {
                            selectEdge(.add)
                        }
                        .accessibilityAction(named: Text("Remove edge from selection")) {
                            selectEdge(.subtract)
                        }
                        .accessibilityActions {
                            if let reveal = revealOwningComponent {
                                Button("Reveal Owning Component", action: reveal)
                            }
                        }
                        .contextMenu {
                            if let reveal = revealOwningComponent {
                                Button("Reveal Owning Component", action: reveal)
                            }
                            Button("Select Whole Part", action: selectWholePart)
                                .disabled(!store.canSelectWholePart(.edge(edge.id)))
                        }
                        .help("\(edge.id) · Shift-click adds; Command-click toggles selection")
                    }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
            .frame(maxHeight: 120)
            .focusedValue(\.editorEdgeSidebarSelectAll, selectAll)
            .disabled(store.isWorking)
        }
    }
}
