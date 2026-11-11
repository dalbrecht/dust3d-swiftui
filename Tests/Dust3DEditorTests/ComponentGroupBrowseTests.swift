import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct BrowseNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading
{
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    { throw CancellationError() }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    { throw CancellationError() }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}

@MainActor final class ComponentGroupBrowseTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='z' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes>
                <edges/><parts><part id='p'/></parts><components>
                <component id='g' name='Group'><component id='one'/><component id='sub'><component id='leaf'/></component></component>
                <component id='other'><component id='owner' linkDataType='partId' linkData='p'/></component>
                </components></canvas>
                """.utf8))
    }

    private func store() -> EditorStore {
        let stub = BrowseNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Group browsing did not settle")
    }

    func testDirectOrderedChildrenAndBreadcrumbs() throws {
        let state = try EditorState(document: source())
        let tree = state.snapshot.componentTree
        let group = try XCTUnwrap(ComponentGroupBrowse(tree: tree, groupID: "g"))
        XCTAssertEqual(group.children.map(\.id), ["one", "sub"])
        XCTAssertEqual(group.path.map(\.id), ["g"])
        let nested = try XCTUnwrap(ComponentGroupBrowse(tree: tree, groupID: "sub"))
        XCTAssertEqual(nested.children.map(\.id), ["leaf"])
        XCTAssertEqual(nested.path.map(\.id), ["g", "sub"])
        XCTAssertNil(ComponentGroupBrowse(tree: tree, groupID: "owner"))
        XCTAssertNil(ComponentGroupBrowse(tree: tree, groupID: "missing"))
    }

    func testSidebarDistinguishesEmptyGroupsFromParts() throws {
        let rows = try EditorState(document: source()).snapshot.componentTree.rows
        let emptyGroup = try XCTUnwrap(rows.first { $0.id == "one" })
        let part = try XCTUnwrap(rows.first { $0.id == "owner" })
        XCTAssertFalse(emptyGroup.hasChildren)
        XCTAssertEqual(emptyGroup.sidebarSymbolName, "folder")
        XCTAssertEqual(emptyGroup.sidebarAccessibilityLabel, "Group \(emptyGroup.title)")
        XCTAssertEqual(part.sidebarSymbolName, "square.stack.3d.up")
        XCTAssertEqual(part.sidebarAccessibilityLabel, "Component \(part.title)")
    }

    func testEnclosingGroupCommandRetiresOnNavigationAndPreservesDocument() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        XCTAssertNil(value.componentBrowseParentAction())
        value.componentBrowseAction("sub", snapshot: try XCTUnwrap(value.snapshot))()
        let up = try XCTUnwrap(value.componentBrowseParentAction())
        up()
        try await settle(value)
        XCTAssertEqual(value.componentGroupBrowse?.path.last?.id, "g")
        value.componentBrowseAction("sub", snapshot: try XCTUnwrap(value.snapshot))()
        up()
        XCTAssertEqual(value.componentGroupBrowse?.path.last?.id, "sub")
        try XCTUnwrap(value.componentBrowseParentAction())()
        try await settle(value)
        try XCTUnwrap(value.componentBrowseParentAction())()
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testBrowseSelectedGroupRequiresVisibleSingleSelectionAndCurrentDisclosure() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        let disclosure = ComponentSidebarDisclosure()

        value.selectComponents(["g", "other"])
        try await settle(value)
        XCTAssertNil(
            value.componentSidebarBrowseSelectionAction(
                snapshot: try XCTUnwrap(value.snapshot), disclosure: disclosure))

        value.selectComponents(["sub"])
        try await settle(value)
        let selected = try XCTUnwrap(value.snapshot)
        let stale = try XCTUnwrap(
            value.componentSidebarBrowseSelectionAction(
                snapshot: selected, disclosure: disclosure))
        disclosure.collapsedIDs = ["g"]
        stale()
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertNil(value.componentSidebarBrowseSelectionAction(snapshot: selected, disclosure: disclosure))
        disclosure.collapsedIDs = []

        let browse = try XCTUnwrap(
            value.componentSidebarBrowseSelectionAction(
                snapshot: selected, disclosure: disclosure))
        browse()
        try await settle(value)
        XCTAssertEqual(value.componentGroupBrowse?.path.map(\.id), ["g", "sub"])
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testBrowseAutomaticallyPlacesToolbarAndPointerPartsWithExactUndo() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        let initial = try XCTUnwrap(value.snapshot)
        value.componentBrowseAction("g", snapshot: initial)()
        let retained = value.addNodeAction(newPart: true)
        value.componentBrowseAction("sub", snapshot: initial)()
        value.componentBrowseAction("g", snapshot: initial)()
        retained()
        XCTAssertFalse(value.isWorking)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)

        value.componentBrowseAction("sub", snapshot: initial)()
        XCTAssertTrue(value.snapshot?.selectedComponentIDs.isEmpty == true)
        value.addNodeAction(newPart: true)()
        try await settle(value)
        XCTAssertEqual(
            value.snapshot?.componentTree.rows.first { $0.component.partID != nil && $0.id != "owner" }?.component
                .parentID, "sub")
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)

        let projection = CanvasProjection(bounds: value.bounds, plane: value.plane, width: 500, height: 300)
        value.setCanvasContext(projection: projection, width: 500, height: 300)
        value.beginAddMode()
        let oldMode = value.addModeID
        value.previewAddAtCanvasCenter()
        let point = try XCTUnwrap(value.addGhostPoint)
        value.componentBrowseAction("g", snapshot: try XCTUnwrap(value.snapshot))()
        XCTAssertFalse(value.isAddingNodes)
        value.placeAddNode(at: point, modeID: oldMode)
        XCTAssertFalse(value.isWorking)

        value.beginAddMode()
        value.previewAddAtCanvasCenter()
        value.placeAddNode(at: try XCTUnwrap(value.addGhostPoint), modeID: value.addModeID)
        try await settle(value)
        XCTAssertEqual(
            value.snapshot?.componentTree.rows.first { $0.component.partID != nil && $0.id != "owner" }?.component
                .parentID, "g")
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testBrowseLeavesAnchoredAddInItsOriginalPart() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        value.select("z")
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        value.componentBrowseAction("g", snapshot: before)()
        let projection = CanvasProjection(bounds: value.bounds, plane: value.plane, width: 500, height: 300)
        value.setCanvasContext(projection: projection, width: 500, height: 300)
        value.beginAddMode()
        XCTAssertEqual(value.addPlacement.anchorID, "z")
        let mode = value.addModeID
        let point = projection.point(for: .init(x: 0.4, y: 0.5, z: 0.5))
        value.updateAddPointer(at: point, modeID: mode)
        value.componentBrowseAction("sub", snapshot: before)()
        XCTAssertEqual(value.addModeID, mode)
        value.placeAddNode(at: point, modeID: mode)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.nodes.map(\.partID), ["p", "p"])
        XCTAssertEqual(value.snapshot?.componentTree.rows.first { $0.id == "owner" }?.component.parentID, "other")
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }

    func testBrowsePlacesNativeAndInteractiveXMLPasteButKeepsOverridesAndStartupRoot() async throws {
        let document = try source()
        let original = document.encoded()
        let standalone = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let fragment = try standalone.copyingNodes(["a"])
        let native = try NodeClipboardPayload(fragment: fragment, identifier: UUID().uuidString).encoded()
        let xml = fragment.document.modelXML
        let value = store()
        defer { value.stop() }
        let fileID = UUID()
        await value.load(data: original, fileIdentity: fileID)
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        value.componentBrowseAction("g", snapshot: before)()
        let retained = try XCTUnwrap(value.clipboardPasteRequest())
        value.chooseQtXMLFile()
        let retainedXML = try XCTUnwrap(value.qtXMLFilePasteRequestID)
        value.componentBrowseAction("sub", snapshot: before)()
        value.componentBrowseAction("g", snapshot: before)()
        value.pasteNodes(data: native, request: retained)
        XCTAssertFalse(value.isWorking)
        let url = URL(fileURLWithPath: "/unused.xml")
        XCTAssertNil(value.finishQtXMLFileChoice(requestID: retainedXML, result: .success([url]), read: { _ in xml }))
        XCTAssertEqual(value.snapshot?.document.encoded(), original)

        value.pasteNodes(data: native)
        try await settle(value)
        XCTAssertEqual(
            value.snapshot?.componentTree.rows.first { $0.component.partID != nil && $0.id != "owner" }?.component
                .parentID, "g")
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)

        value.chooseQtXMLFile()
        let interactive = try XCTUnwrap(value.qtXMLFilePasteRequestID)
        let operation = try XCTUnwrap(
            value.finishQtXMLFileChoice(requestID: interactive, result: .success([url]), read: { _ in xml }))
        await operation.value
        XCTAssertEqual(
            value.snapshot?.componentTree.rows.first { $0.component.partID != nil && $0.id != "owner" }?.component
                .parentID, "g")
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)

        for (destination, parentID): (AddPlacementDestination, String?) in [
            (.documentRoot, nil), (.group("other"), "other"),
        ] {
            value.workingGroupAction(destination, snapshot: try XCTUnwrap(value.snapshot))()
            value.pasteNodes(data: native)
            try await settle(value)
            let pasted = try XCTUnwrap(
                value.snapshot?.componentTree.rows.first { $0.component.partID != nil && $0.id != "owner" })
            XCTAssertEqual(pasted.component.parentID, parentID)
            value.undo()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original)
        }

        await value.load(data: original, fileIdentity: fileID)
        try await settle(value)
        value.componentBrowseAction("g", snapshot: try XCTUnwrap(value.snapshot))()
        let startup = try XCTUnwrap(value.applyStartupQtXML(xml, fileIdentity: fileID))
        await startup.value
        let pasted = try XCTUnwrap(
            value.snapshot?.componentTree.rows.first { $0.component.partID != nil && $0.id != "owner" })
        XCTAssertNil(pasted.component.parentID)
    }

    func testPrimaryActivationBrowsesFromTheFullTreeAndRetiresOldRows() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        let initial = try XCTUnwrap(value.snapshot)
        let visible = initial.componentTree.visibleRows(collapsing: [])
        let disclosure = ComponentSidebarDisclosure()
        let staleDisclosure = value.componentSidebarPrimaryAction(
            snapshot: initial, rows: visible, scopeEpoch: value.componentBrowseEpoch, disclosure: disclosure)
        disclosure.collapsedIDs = ["g"]
        staleDisclosure(["g"])
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertEqual(disclosure.collapsedIDs, ["g"])
        disclosure.collapsedIDs = []
        let rootActivate = value.componentSidebarPrimaryAction(
            snapshot: initial, rows: visible, scopeEpoch: value.componentBrowseEpoch, disclosure: disclosure)
        rootActivate(["g", "other"])
        XCTAssertNil(value.componentGroupBrowse)

        rootActivate(["g"])
        try await settle(value)
        XCTAssertEqual(value.componentGroupBrowse?.path.last?.id, "g")
        XCTAssertEqual(value.componentGroupBrowse?.children.map(\.id), ["one", "sub"])
        rootActivate(["other"])
        XCTAssertEqual(value.componentGroupBrowse?.path.last?.id, "g")
        let scoped = try XCTUnwrap(value.snapshot)
        value.componentBrowseAction(nil, snapshot: scoped)()
        XCTAssertNil(value.componentGroupBrowse)
        rootActivate(["g"])
        XCTAssertNil(value.componentGroupBrowse)

        let next = try XCTUnwrap(value.snapshot)
        disclosure.collapsedIDs = ["other"]
        let collapsed = value.componentSidebarPrimaryAction(
            snapshot: next, rows: next.componentTree.visibleRows(collapsing: disclosure.collapsedIDs),
            scopeEpoch: value.componentBrowseEpoch, disclosure: disclosure)
        collapsed(["owner"])
        XCTAssertFalse(value.isWorking)
        disclosure.collapsedIDs = []
        let expanded = value.componentSidebarPrimaryAction(
            snapshot: next, rows: next.componentTree.visibleRows(collapsing: []),
            scopeEpoch: value.componentBrowseEpoch, disclosure: disclosure)
        expanded(["owner"])
        try await settle(value)
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["z"])
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testBrowsingPreservesGraphAndWorkingGroupAndRejectsRetainedScope() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        value.select("z")
        try await settle(value)
        let snapshot = try XCTUnwrap(value.snapshot)
        value.workingGroupAction(.group("other"), snapshot: snapshot)()
        let oldScope = value.componentBrowseEpoch
        let oldNavigation = value.componentBrowseAction("sub", snapshot: snapshot)
        let oldSelectAll = ComponentSidebarSelectAllTarget(
            snapshot: snapshot, visibleIDs: ["g", "other"], scopeEpoch: oldScope)
        value.componentBrowseAction("g", snapshot: snapshot)()
        XCTAssertEqual(value.componentGroupBrowse?.path.map(\.id), ["g"])
        XCTAssertEqual(value.snapshot?.selectedIDs, ["z"])
        XCTAssertEqual(value.addPlacementDestination, .group("other"))
        XCTAssertFalse(value.canSelectAllVisibleComponents(oldSelectAll))
        oldNavigation()
        XCTAssertEqual(value.componentGroupBrowse?.path.map(\.id), ["g"])
        let scoped = ComponentSidebarSelectAllTarget(
            snapshot: try XCTUnwrap(value.snapshot), visibleIDs: ["one", "sub"], scopeEpoch: value.componentBrowseEpoch)
        value.selectAllVisibleComponents(scoped)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["one", "sub"])
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testNavigationPrunesHiddenPicksAndOutsideRevealReturnsToFullTree() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        value.selectComponents(["one", "g", "other"])
        try await settle(value)
        let initial = try XCTUnwrap(value.snapshot)
        value.componentBrowseAction("g", snapshot: initial)()
        try await settle(value)
        XCTAssertEqual(value.componentGroupBrowse?.path.map(\.id), ["g"])
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["one"])
        let scoped = try XCTUnwrap(value.snapshot)
        let retained = value.componentBrowseAction("sub", snapshot: scoped)
        let reveal = try XCTUnwrap(
            value.revealOwningComponentAction(.node("z"), context: .init(snapshot: scoped)))
        reveal()
        try await settle(value)
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertEqual(value.snapshot?.componentRevealHint?.componentID, "owner")
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["one"])
        retained()
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testGroupingActionRejectsRetiredScopeAndAppliesOnlyCapturedSelection() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        value.componentBrowseAction("g", snapshot: try XCTUnwrap(value.snapshot))()
        value.selectComponents(["one", "sub"])
        try await settle(value)
        let rendered = try XCTUnwrap(value.snapshot)
        let oldScope = value.componentBrowseEpoch
        let retired = value.componentGroupingAction(snapshot: rendered, scopeEpoch: oldScope)
        value.componentBrowseAction(nil, snapshot: rendered)()
        value.componentBrowseAction("g", snapshot: rendered)()
        XCTAssertNotEqual(value.componentBrowseEpoch, oldScope)
        XCTAssertEqual(value.snapshot?.selectionRevision, rendered.selectionRevision)
        retired()
        XCTAssertFalse(value.isWorking)
        XCTAssertFalse(value.canUndo)

        let staleSelection = value.componentGroupingAction(snapshot: rendered, scopeEpoch: value.componentBrowseEpoch)
        value.selectComponents(["one"])
        try await settle(value)
        value.selectComponents(["one", "sub"])
        try await settle(value)
        staleSelection()
        XCTAssertFalse(value.isWorking)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)

        let current = try XCTUnwrap(value.snapshot)
        value.componentGroupingAction(snapshot: current, scopeEpoch: value.componentBrowseEpoch)()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedComponent?.childIDs, ["one", "sub"])
        XCTAssertTrue(value.canUndo)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)

        value.selectComponents(["one", "sub"])
        try await settle(value)
        let beforeFailure = try XCTUnwrap(value.snapshot)
        let staleSource = value.componentGroupingAction(snapshot: beforeFailure, scopeEpoch: value.componentBrowseEpoch)
        XCTAssertTrue(value.canGroupComponents)
        await value.load(data: Data("invalid archive".utf8))
        XCTAssertFalse(value.canGroupComponents)
        staleSource()
        XCTAssertFalse(value.isWorking)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }

    func testRenderedRowContextRejectsTopologyChangesWithinSameBrowseScope() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        value.componentBrowseAction("g", snapshot: try XCTUnwrap(value.snapshot))()
        let rendered = try XCTUnwrap(value.snapshot)
        let context = PartGraphSelectionContext(snapshot: rendered)
        let scope = value.componentBrowseEpoch
        XCTAssertTrue(value.admitsComponentSidebarInput(context: context, scopeEpoch: scope))

        value.selectComponents(["one", "sub"])
        try await settle(value)
        XCTAssertTrue(value.admitsComponentSidebarInput(context: context, scopeEpoch: scope))
        value.groupSelectedComponents()
        try await settle(value)
        XCTAssertEqual(value.componentBrowseEpoch, scope)
        XCTAssertFalse(value.admitsComponentSidebarInput(context: context, scopeEpoch: scope))
        let updated = PartGraphSelectionContext(snapshot: try XCTUnwrap(value.snapshot))
        XCTAssertTrue(value.admitsComponentSidebarInput(context: updated, scopeEpoch: scope))
    }

    func testNestedNavigationRetiresOldDragAndDeletedScope() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        let snapshot = try XCTUnwrap(value.snapshot)
        value.componentBrowseAction("g", snapshot: snapshot)()
        let drag = try XCTUnwrap(value.beginComponentDrag(grabbedID: "one"))
        value.componentBrowseAction("sub", snapshot: snapshot)()
        XCTAssertEqual(value.componentGroupBrowse?.path.map(\.id), ["g", "sub"])
        XCTAssertFalse(value.dropComponents(token: drag, in: .root))
        value.componentBrowseAction("g", snapshot: snapshot)()
        XCTAssertEqual(value.componentGroupBrowse?.path.map(\.id), ["g"])
        value.componentBrowseAction("sub", snapshot: snapshot)()
        value.componentDeletionAction(ComponentDeletionTarget(snapshot: snapshot, componentIDs: ["sub"]))()
        try await settle(value)
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertTrue(value.canUndo)
        value.undo()
        try await settle(value)
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        value.componentBrowseAction("g", snapshot: try XCTUnwrap(value.snapshot))()
        await value.load(data: original)
        XCTAssertNil(value.componentGroupBrowse)
    }

}
