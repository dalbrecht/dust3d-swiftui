import Dust3DEditorModel
import SwiftUI

struct ComponentSidebar: View {
    let store: EditorStore
    @State private var disclosure: ComponentSidebarDisclosure

    init(store: EditorStore, disclosure: ComponentSidebarDisclosure = ComponentSidebarDisclosure()) {
        self.store = store
        _disclosure = State(initialValue: disclosure)
    }

    var body: some View {
        let deletionSnapshot = store.snapshot
        return Group {
            if let tree = store.snapshot?.componentTree, !tree.rows.isEmpty || tree.failureDescription != nil {
                Divider()
                HStack {
                    ComponentParentDropZone(store: store, parent: .root) {
                        Text("Components").font(.headline)
                    }
                    .help("Drop here to move components to the document root.")
                    Spacer()
                    Menu {
                        Menu("Select Only…") {
                            ForEach(store.snapshot?.selectedComponentRows ?? []) { row in
                                Button(row.title) { store.selectOnlyComponent(row.id) }
                                    .accessibilityLabel("Select only \(row.title)")
                                    .help(row.id)
                            }
                        }
                        .disabled(store.snapshot?.selectedComponentIDs.count ?? 0 < 2)
                        if let deletionSnapshot {
                            ComponentDeletionButton(
                                store: store, target: ComponentDeletionTarget(snapshot: deletionSnapshot))
                        }
                        Button("Clear Component Selection") { store.clearComponentSelection() }
                            .disabled(store.snapshot?.selectedComponentIDs.isEmpty != false)
                        Divider()
                        if let snapshot = store.snapshot {
                            selectInCanvasButton(snapshot: snapshot, ids: snapshot.selectedComponentIDs)
                        }
                        ComponentPartRoleMenu(store: store)
                        if let snapshot = store.snapshot {
                            ComponentBatchPartStateMenu(
                                store: store, target: ComponentMeshSelectionTarget(snapshot: snapshot))
                        }
                        Button("Group Selected Components") { store.groupSelectedComponents() }
                            .disabled(!store.canGroupComponents)
                        if let snapshot = store.snapshot {
                            ComponentUngroupButton(
                                store: store, target: ComponentUngroupTarget(snapshot: snapshot))
                        }
                        Divider()
                        Button("Collapse Selected Group") {
                            if let id = store.snapshot?.selectedComponentID { disclosure.collapsedIDs.insert(id) }
                        }
                        .disabled(
                            store.snapshot?.selectedComponent?.childIDs.isEmpty != false
                                || store.snapshot?.selectedComponentID.map { disclosure.collapsedIDs.contains($0) }
                                    != false
                        )
                        Button("Expand Selected Group") {
                            if let id = store.snapshot?.selectedComponentID { disclosure.collapsedIDs.remove(id) }
                        }
                        .disabled(
                            store.snapshot?.selectedComponent?.childIDs.isEmpty != false
                                || store.snapshot?.selectedComponentID.map { disclosure.collapsedIDs.contains($0) }
                                    != true
                        )
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
                    ScrollViewReader { proxy in
                        let revealKey = revealScrollKey(tree: tree)
                        let documentIdentity = store.snapshot?.documentIdentity
                        List(
                            selection: Binding(
                                get: { store.snapshot?.selectedComponentIDs ?? [] },
                                set: {
                                    if $0 != store.snapshot?.selectedComponentIDs { store.selectComponents($0) }
                                }
                            )
                        ) {
                            ForEach(tree.visibleRows(collapsing: disclosure.collapsedIDs)) { row in
                                HStack(spacing: 4) {
                                    if row.hasChildren {
                                        Button {
                                            if disclosure.collapsedIDs.contains(row.id) {
                                                disclosure.collapsedIDs.remove(row.id)
                                            } else {
                                                disclosure.collapsedIDs.insert(row.id)
                                            }
                                        } label: {
                                            Image(
                                                systemName: disclosure.collapsedIDs.contains(row.id)
                                                    ? "chevron.right" : "chevron.down"
                                            )
                                        }
                                        .frame(width: 12)
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(
                                            "\(disclosure.collapsedIDs.contains(row.id) ? "Expand" : "Collapse") \(row.title)"
                                        )
                                    } else {
                                        Color.clear.frame(width: 12, height: 1).accessibilityHidden(true)
                                    }
                                    Label(row.title, systemImage: row.hasChildren ? "folder" : "square.stack.3d.up")
                                        .lineLimit(1)
                                }
                                .padding(.leading, CGFloat(min(row.depth, 6) * 10))
                                .modifier(ComponentRowDrag(store: store, id: row.id, isGroup: row.component.isGroup))
                                .tag(row.id)
                                .id(row.id)
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("Component \(row.title)")
                                .help("\(row.title) · \(row.id)")
                            }
                        }
                        .contextMenu(forSelectionType: String.self) { ids in
                            if let snapshot = store.snapshot, snapshot.documentIdentity == documentIdentity,
                                !ids.isEmpty
                            {
                                selectInCanvasButton(snapshot: snapshot, ids: ids)
                                ComponentDeletionButton(
                                    store: store,
                                    target: ComponentDeletionTarget(snapshot: snapshot, componentIDs: Array(ids)))
                                ComponentUngroupButton(
                                    store: store,
                                    target: ComponentUngroupTarget(snapshot: snapshot, componentIDs: Array(ids)))
                            }
                        } primaryAction: { ids in
                            guard ids.count == 1, let id = ids.first, let snapshot = store.snapshot, !store.isWorking,
                                snapshot.documentIdentity == documentIdentity,
                                let row = snapshot.componentTree.rows.first(where: { $0.id == id })
                            else { return }
                            if row.hasChildren {
                                disclosure.collapsedIDs.remove(id)
                            } else {
                                store.selectComponentGraph(
                                    ComponentGraphSelectionTarget(snapshot: snapshot, componentIDs: ids))
                            }
                        }
                        .focusedValue(\.editorComponentSidebarFocus, true)
                        .onDeleteCommand {
                            guard let deletionSnapshot else { return }
                            store.componentDeletionAction(ComponentDeletionTarget(snapshot: deletionSnapshot))()
                        }
                        .listStyle(.sidebar)
                        .frame(maxHeight: 120)
                        .disabled(store.isWorking)
                        .onChange(of: store.snapshot?.componentRevealHint?.revision, initial: true) { _, _ in
                            guard let snapshot = store.snapshot, let hint = snapshot.componentRevealHint else { return }
                            disclosure.reveal(hint)
                        }
                        .task(id: revealKey) { @MainActor in
                            guard revealKey != nil, let hint = store.snapshot?.componentRevealHint else { return }
                            await Task.yield()
                            guard !Task.isCancelled, store.snapshot?.documentIdentity == documentIdentity,
                                store.snapshot?.componentRevealHint?.revision == hint.revision
                            else { return }
                            proxy.scrollTo(hint.componentID, anchor: .center)
                        }
                    }
                }
            }
        }
        .onChange(of: store.snapshot?.documentIdentity) { _, _ in disclosure.collapsedIDs = [] }
    }
    private func selectInCanvasButton(snapshot: EditorSnapshot, ids: Set<String>) -> some View {
        let target = ComponentGraphSelectionTarget(snapshot: snapshot, componentIDs: ids)
        return Button("Select in Canvas") { store.selectComponentGraph(target) }
            .disabled(!snapshot.canSelectComponentGraph(target))
            .help("Select editable nodes and edges in these components and their descendants.")
    }

    private func revealScrollKey(tree: ComponentTree) -> String? {
        guard let snapshot = store.snapshot, let hint = snapshot.componentRevealHint,
            tree.visibleRows(collapsing: disclosure.collapsedIDs).contains(where: { $0.id == hint.componentID })
        else { return nil }
        return "\(snapshot.documentIdentity)-\(hint.revision)"
    }

}
