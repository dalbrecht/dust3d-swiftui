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
        let rigEligible = store.rigEdgeSidebarEligibleIDs
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
                        let from = titles[edge.fromID] ?? edge.fromID
                        let to = titles[edge.toID] ?? edge.toID
                        let isSelected = store.snapshot?.selectedEdgeIDs.contains(edge.id) == true
                        let canPick = rigEligible?.contains(Data(edge.id.utf8)) ?? true
                        Button {
                            let flags = NSApp.currentEvent?.modifierFlags ?? []
                            if !canPick {
                                selectEdge(.subtract)
                            } else if flags.contains(.command) {
                                selectEdge(.toggle)
                            } else if flags.contains(.shift) {
                                selectEdge(.add)
                            } else {
                                selectEdge(.replace)
                            }
                        } label: {
                            Label(
                                "\(from) → \(to)",
                                systemImage: isSelected ? "checkmark.circle.fill" : "line.diagonal"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(isSelected ? .accentColor : .secondary)
                        .disabled(!canPick && !isSelected)
                        .accessibilityLabel(
                            canPick || !isSelected
                                ? "Select edge from \(from) to \(to)" : "Remove edge from \(from) to \(to)"
                        )
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityValue(
                            canPick
                                ? (isSelected ? "Selected" : "Not selected")
                                : (isSelected
                                    ? "Selected, unavailable for bone assignment" : "Unavailable for bone assignment")
                        )
                        .accessibilityActions {
                            if canPick && !isSelected {
                                Button("Add edge to selection") { selectEdge(.add) }
                            }
                            if isSelected {
                                Button("Remove edge from selection") { selectEdge(.subtract) }
                            }
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
                        .help(
                            canPick
                                ? "\(edge.id) · Shift-click adds; Command-click toggles selection"
                                : (isSelected
                                    ? "Remove this unavailable edge from the selection."
                                    : "Unavailable for bone assignment.")
                        )
                    }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
            .frame(maxHeight: 120)
            .focusedValue(\.editorEdgeSidebarSelectAll, selectAll)
            .disabled(store.isWorking || !store.canPickGraph)
        }
    }
}
