import AppKit
import Dust3DEditorModel
import SwiftUI

/// An accessible alternative to pointer picking, including edges whose projection collapses to a point.
struct EdgeSidebar: View {
    let store: EditorStore

    var body: some View {
        let edges = store.snapshot?.edges ?? []
        let titles = Dictionary(uniqueKeysWithValues: (store.snapshot?.nodes ?? []).map { ($0.id, $0.title) })
        let partContext = store.snapshot.map { PartGraphSelectionContext(snapshot: $0) }
        if let selectAll = store.edgeSidebarSelectAllTarget {
            Divider()
            Text("Edges").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(edges) { edge in
                        let selectEdge = store.edgeSidebarSelectionAction(edge.id, context: partContext)
                        let selectWholePart = store.wholePartSelectionAction(.edge(edge.id))
                        let revealOwningComponent = store.revealOwningComponentAction(
                            .edge(edge.id), context: partContext)
                        let title = "\(titles[edge.fromID] ?? edge.fromID) → \(titles[edge.toID] ?? edge.toID)"
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
                                systemImage: store.snapshot?.selectedEdgeIDs.contains(edge.id) == true
                                    ? "checkmark.circle.fill" : "line.diagonal"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.snapshot?.selectedEdgeIDs.contains(edge.id) == true ? .accentColor : .secondary)
                        .accessibilityLabel(
                            "Select edge from \(titles[edge.fromID] ?? edge.fromID) to \(titles[edge.toID] ?? edge.toID)"
                        )
                        .accessibilityAddTraits(
                            store.snapshot?.selectedEdgeIDs.contains(edge.id) == true ? .isSelected : []
                        )
                        .accessibilityValue(
                            store.snapshot?.selectedEdgeIDs.contains(edge.id) == true ? "Selected" : "Not selected"
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
