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
            if let sidebarSnapshot = deletionSnapshot,
                !sidebarSnapshot.componentTree.rows.isEmpty || sidebarSnapshot.componentTree.failureDescription != nil
            {
                let tree = sidebarSnapshot.componentTree
                let browse = store.componentGroupBrowse
                let scopeEpoch = store.componentBrowseEpoch
                let admitsScope: @MainActor () -> Bool = { store.componentBrowseEpoch == scopeEpoch }
                Divider()
                HStack {
                    ComponentParentDropZone(store: store, parent: .root, scopeEpoch: scopeEpoch) {
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
                                store: store, target: ComponentDeletionTarget(snapshot: deletionSnapshot),
                                admitsInput: admitsScope)
                        }
                        Button("Clear Component Selection") { store.clearComponentSelection() }
                            .disabled(store.snapshot?.selectedComponentIDs.isEmpty != false)
                        Divider()
                        if let snapshot = store.snapshot {
                            selectInCanvasButton(
                                snapshot: snapshot, ids: snapshot.selectedComponentIDs, admitsInput: admitsScope)
                        }
                        if let group = sidebarSnapshot.selectedComponent, group.isGroup {
                            browseButton(group.id, snapshot: sidebarSnapshot)
                        }
                        if let id = sidebarSnapshot.selectedComponentID,
                            let target = ComponentPlacementTarget(snapshot: sidebarSnapshot, singleComponentID: id)
                        {
                            ComponentSidebarOrderMenu(store: store, target: target, scopeEpoch: scopeEpoch)
                        }
                        ComponentPartRoleMenu(store: store)
                        if let snapshot = store.snapshot {
                            ComponentBatchPartStateMenu(
                                store: store, target: ComponentMeshSelectionTarget(snapshot: snapshot))
                        }
                        Group {
                            if let groupID = sidebarSnapshot.selectedComponentID,
                                sidebarSnapshot.addPlacementGroup(groupID) != nil
                            {
                                Button(
                                    "Set Working Group",
                                    action: store.workingGroupAction(.group(groupID), snapshot: sidebarSnapshot)
                                )
                                .disabled(store.addPlacementDestination == .group(groupID))
                            }
                            Button(
                                "Use Document Root",
                                action: store.workingGroupAction(.documentRoot, snapshot: sidebarSnapshot)
                            )
                            .disabled(store.addPlacementDestination == .documentRoot)
                            Button(
                                "Use Selected Group for Pointer Add",
                                action: store.workingGroupAction(.selection, snapshot: sidebarSnapshot)
                            )
                            .disabled(store.addPlacementDestination == .selection)
                        }
                        .disabled(!store.canChooseAddPlacementDestination)
                        Divider()
                        Button(
                            "Group Selected Components",
                            action: store.componentGroupingAction(snapshot: sidebarSnapshot, scopeEpoch: scopeEpoch)
                        )
                        .disabled(!store.canGroupComponents)
                        if let snapshot = store.snapshot {
                            ComponentUngroupButton(
                                store: store, target: ComponentUngroupTarget(snapshot: snapshot),
                                admitsInput: admitsScope)
                        }
                        Divider()
                        Button("Collapse Selected Group") {
                            if let id = store.snapshot?.selectedComponentID { disclosure.collapsedIDs.insert(id) }
                        }
                        .disabled(
                            browse != nil || store.snapshot?.selectedComponent?.childIDs.isEmpty != false
                                || store.snapshot?.selectedComponentID.map { disclosure.collapsedIDs.contains($0) }
                                    != false
                        )
                        Button("Expand Selected Group") {
                            if let id = store.snapshot?.selectedComponentID { disclosure.collapsedIDs.remove(id) }
                        }
                        .disabled(
                            browse != nil || store.snapshot?.selectedComponent?.childIDs.isEmpty != false
                                || store.snapshot?.selectedComponentID.map { disclosure.collapsedIDs.contains($0) }
                                    != true
                        )
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Component tree actions")
                    .disabled(store.isWorking)
                }.padding(12)
                Label("Add destination: \(store.addPlacementDestinationTitle)", systemImage: "folder.badge.plus")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                    .help(
                        "An explicit working group receives new parts and pasted components. Automatic placement uses the selected group for canvas Add and the document root for menu Add and Paste. Extending a chain keeps its part."
                    )
                if let count = store.snapshot?.selectedComponentIDs.count, count > 1 {
                    Text("\(count) components selected")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                }
                if let browse {
                    browsePath(browse, snapshot: sidebarSnapshot)
                    if browse.children.isEmpty {
                        Text("No components in this group.").font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                    }
                }
                if let failure = tree.failureDescription {
                    Label(
                        "Hierarchy unavailable: \(failure). Source data is preserved.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 12)
                } else {
                    ScrollViewReader { proxy in
                        let visibleRows = browse?.children ?? tree.visibleRows(collapsing: disclosure.collapsedIDs)
                        let revealKey = revealScrollKey(visibleRows: visibleRows)
                        let documentIdentity = sidebarSnapshot.documentIdentity
                        let context = PartGraphSelectionContext(snapshot: sidebarSnapshot)
                        let admitsRows: @MainActor () -> Bool = {
                            store.admitsComponentSidebarInput(context: context, scopeEpoch: scopeEpoch)
                        }
                        List(
                            selection: Binding(
                                get: { store.snapshot?.selectedComponentIDs ?? [] },
                                set: {
                                    if $0 != store.snapshot?.selectedComponentIDs {
                                        store.selectBrowsedComponents($0, scopeEpoch: scopeEpoch)
                                    }
                                }
                            )
                        ) {
                            ForEach(visibleRows) { row in
                                componentRow(row, scoped: browse != nil, scopeEpoch: scopeEpoch)
                            }
                        }
                        .contextMenu(forSelectionType: String.self) { ids in
                            let visibleKeys = Set(visibleRows.map { Data($0.id.utf8) })
                            if admitsRows(), !ids.isEmpty, ids.allSatisfy({ visibleKeys.contains(Data($0.utf8)) }) {
                                if ids.count == 1, let id = ids.first,
                                    visibleRows.contains(where: {
                                        $0.id.utf8.elementsEqual(id.utf8) && $0.component.isGroup
                                    })
                                {
                                    browseButton(id, snapshot: sidebarSnapshot)
                                }
                                if ids.count == 1, let id = ids.first,
                                    let target = ComponentPlacementTarget(
                                        snapshot: sidebarSnapshot, singleComponentID: id)
                                {
                                    ComponentSidebarOrderMenu(store: store, target: target, scopeEpoch: scopeEpoch)
                                }
                                selectInCanvasButton(snapshot: sidebarSnapshot, ids: ids, admitsInput: admitsRows)
                                ComponentDeletionButton(
                                    store: store,
                                    target: ComponentDeletionTarget(
                                        snapshot: sidebarSnapshot, componentIDs: Array(ids)),
                                    admitsInput: admitsRows)
                                ComponentUngroupButton(
                                    store: store,
                                    target: ComponentUngroupTarget(snapshot: sidebarSnapshot, componentIDs: Array(ids)),
                                    admitsInput: admitsRows)
                            }
                        } primaryAction: { ids in
                            guard admitsRows(), ids.count == 1, let id = ids.first,
                                let row = visibleRows.first(where: { $0.id.utf8.elementsEqual(id.utf8) })
                            else { return }
                            if browse != nil, row.component.isGroup {
                                store.componentBrowseAction(id, snapshot: sidebarSnapshot)()
                            } else if row.hasChildren {
                                disclosure.collapsedIDs.remove(id)
                            } else {
                                store.selectComponentGraph(
                                    ComponentGraphSelectionTarget(snapshot: sidebarSnapshot, componentIDs: ids))
                            }
                        }
                        .focusedValue(\.editorComponentSidebarFocus, true)
                        .focusedValue(
                            \.editorComponentSidebarSelectAll,
                            ComponentSidebarSelectAllTarget(
                                snapshot: sidebarSnapshot, visibleIDs: Set(visibleRows.map(\.id)),
                                scopeEpoch: scopeEpoch)
                        )
                        .onDeleteCommand {
                            guard admitsScope(), let deletionSnapshot else { return }
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
                            guard !Task.isCancelled, admitsScope(),
                                store.snapshot?.documentIdentity == documentIdentity,
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
    private func componentRow(_ row: ComponentTreeRow, scoped: Bool, scopeEpoch: UUID) -> some View {
        HStack(spacing: 4) {
            if !scoped && row.hasChildren {
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
        .padding(.leading, !scoped ? CGFloat(min(row.depth, 6) * 10) : 0)
        .modifier(
            ComponentRowDrag(
                store: store, id: row.id, isGroup: row.component.isGroup, scopeEpoch: scopeEpoch
            )
        )
        .tag(row.id)
        .id(row.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Component \(row.title)")
        .help("\(row.title) · \(row.id)")
    }

    private func browseButton(_ id: String, snapshot: EditorSnapshot) -> some View {
        Button("Browse Group", action: store.componentBrowseAction(id, snapshot: snapshot))
            .disabled(!store.canBrowseComponents)
    }

    private func browsePath(_ browse: ComponentGroupBrowse, snapshot: EditorSnapshot) -> some View {
        let ancestors = browse.path.dropLast()
        let parent = ancestors.last
        let scopeEpoch = store.componentBrowseEpoch
        return VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                if let parent {
                    ComponentParentDropZone(store: store, parent: .component(parent.id), scopeEpoch: scopeEpoch) {
                        Button(action: store.componentBrowseAction(parent.id, snapshot: snapshot)) {
                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: "chevron.up").foregroundStyle(.secondary)
                                Text(parent.title)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .help("Browse or drop components into \(parent.title).")
                } else {
                    Button(
                        "Up", systemImage: "chevron.up", action: store.componentBrowseAction(nil, snapshot: snapshot)
                    )
                    .help("Return to the full component tree.")
                }
                HStack(alignment: .top, spacing: 4) {
                    Text(browse.path.last?.title ?? "Group")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Menu {
                        Button("Full Component Tree", action: store.componentBrowseAction(nil, snapshot: snapshot))
                        ForEach(ancestors) { row in
                            Button(row.title, action: store.componentBrowseAction(row.id, snapshot: snapshot))
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Group breadcrumb")
                    .accessibilityValue(browse.path.map(\.title).joined(separator: " › "))
                }
            }
            if ancestors.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(ancestors.dropLast()) { row in
                            ComponentParentDropZone(store: store, parent: .component(row.id), scopeEpoch: scopeEpoch) {
                                Button(row.title, action: store.componentBrowseAction(row.id, snapshot: snapshot))
                            }
                            .help("Browse or drop components into \(row.title).")
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .focusedValue(\.editorComponentSidebarFocus, true)
        .focusedValue(
            \.editorComponentSidebarSelectAll,
            ComponentSidebarSelectAllTarget(
                snapshot: snapshot, visibleIDs: Set(browse.children.map(\.id)), scopeEpoch: store.componentBrowseEpoch)
        )
        .controlSize(.small)
        .disabled(!store.canBrowseComponents)
        .padding(.horizontal, 12)
    }

    private func selectInCanvasButton(
        snapshot: EditorSnapshot, ids: Set<String>, admitsInput: @escaping @MainActor () -> Bool = { true }
    ) -> some View {
        let target = ComponentGraphSelectionTarget(snapshot: snapshot, componentIDs: ids)
        return Button("Select in Canvas") { if admitsInput() { store.selectComponentGraph(target) } }
            .disabled(store.isSelectingRigEdges || !snapshot.canSelectComponentGraph(target))
            .help("Select editable nodes and edges in these components and their descendants.")
    }

    private func revealScrollKey(visibleRows: [ComponentTreeRow]) -> String? {
        guard let snapshot = store.snapshot, let hint = snapshot.componentRevealHint,
            visibleRows.contains(where: { $0.id == hint.componentID })
        else { return nil }
        return "\(snapshot.documentIdentity)-\(hint.revision)"
    }

}
