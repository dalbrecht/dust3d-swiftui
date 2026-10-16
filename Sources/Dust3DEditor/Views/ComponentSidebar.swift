import Dust3DEditorModel
import SwiftUI

struct ComponentSidebar: View {
    let store: EditorStore
    @State private var collapsedIDs: Set<String> = []

    var body: some View {
        Group {
            if let tree = store.snapshot?.componentTree, !tree.rows.isEmpty || tree.failureDescription != nil {
                Divider()
                HStack {
                    Text("Components").font(.headline)
                    Spacer()
                    Menu {
                        Button("Collapse Selected Group") {
                            if let id = store.snapshot?.selectedComponentID { collapsedIDs.insert(id) }
                        }
                        .disabled(store.snapshot?.selectedComponentID.map { collapsedIDs.contains($0) } != false)
                        Button("Expand Selected Group") {
                            if let id = store.snapshot?.selectedComponentID { collapsedIDs.remove(id) }
                        }
                        .disabled(store.snapshot?.selectedComponentID.map { collapsedIDs.contains($0) } != true)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Component tree actions")
                    .disabled(store.isWorking || store.snapshot?.selectedComponent?.childIDs.isEmpty != false)
                }.padding(12)
                if let failure = tree.failureDescription {
                    Label(
                        "Hierarchy unavailable: \(failure). Source data is preserved.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 12)
                } else {
                    List(
                        selection: Binding(
                            get: { store.snapshot?.selectedComponentID }, set: { store.selectComponent($0) })
                    ) {
                        ForEach(tree.visibleRows(collapsing: collapsedIDs)) { row in
                            HStack(spacing: 4) {
                                if row.hasChildren {
                                    Button {
                                        if collapsedIDs.contains(row.id) {
                                            collapsedIDs.remove(row.id)
                                        } else {
                                            collapsedIDs.insert(row.id)
                                        }
                                    } label: {
                                        Image(
                                            systemName: collapsedIDs.contains(row.id) ? "chevron.right" : "chevron.down"
                                        )
                                    }
                                    .frame(width: 12)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        "\(collapsedIDs.contains(row.id) ? "Expand" : "Collapse") \(row.title)")
                                } else {
                                    Color.clear.frame(width: 12, height: 1).accessibilityHidden(true)
                                }
                                Label(row.title, systemImage: row.hasChildren ? "folder" : "square.stack.3d.up")
                                    .lineLimit(1)
                            }
                            .padding(.leading, CGFloat(min(row.depth, 6) * 10))
                            .tag(row.id)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Component \(row.title)")
                            .help("\(row.title) · \(row.id)")
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(maxHeight: 120)
                    .disabled(store.isWorking)
                }
            }
        }
        .onChange(of: store.snapshot?.documentIdentity) { _, _ in collapsedIDs = [] }
    }
}
