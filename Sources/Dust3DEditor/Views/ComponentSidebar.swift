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
                        Button("Group Selected Components") { store.groupSelectedComponents() }
                            .disabled(!store.canGroupComponents)
                        Button("Ungroup Selected Component") { store.ungroupSelectedComponent() }
                            .disabled(!store.canUngroupComponent)
                        Divider()
                        Button("Collapse Selected Group") {
                            if let id = store.snapshot?.selectedComponentID { collapsedIDs.insert(id) }
                        }
                        .disabled(
                            store.snapshot?.selectedComponent?.childIDs.isEmpty != false
                                || store.snapshot?.selectedComponentID.map { collapsedIDs.contains($0) } != false)
                        Button("Expand Selected Group") {
                            if let id = store.snapshot?.selectedComponentID { collapsedIDs.remove(id) }
                        }
                        .disabled(
                            store.snapshot?.selectedComponent?.childIDs.isEmpty != false
                                || store.snapshot?.selectedComponentID.map { collapsedIDs.contains($0) } != true)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Component tree actions")
                    .disabled(store.isWorking)
                }.padding(12)
                if let count = store.snapshot?.selectedComponentIDs.count, count > 1 {
                    Text("\(count) components selected")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                }
                if let failure = tree.failureDescription {
                    Label(
                        "Hierarchy unavailable: \(failure). Source data is preserved.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 12)
                } else {
                    List(
                        selection: Binding(
                            get: { store.snapshot?.selectedComponentIDs ?? [] }, set: { store.selectComponents($0) })
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
