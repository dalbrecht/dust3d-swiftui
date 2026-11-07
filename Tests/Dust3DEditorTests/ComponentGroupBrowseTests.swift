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

    func testBatchStitchingEntersNewGroupWithSelectedChildrenAndExactUndo() async throws {
        let original = try stitchingSource(reusingGroup: false)
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.workingGroupAction(.group("keep"), snapshot: try XCTUnwrap(value.snapshot))()
        value.selectComponents(["a", "b", "keep"])
        try await settle(value)
        let oldScope = value.componentBrowseEpoch
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        value.componentPartRoleAction(.stitchingLine)()
        try await settle(value)

        let snapshot = try XCTUnwrap(value.snapshot)
        let browse = try XCTUnwrap(value.componentGroupBrowse)
        let group = try XCTUnwrap(browse.path.last)
        XCTAssertEqual(browse.children.map(\.id), ["a", "b"])
        XCTAssertEqual(snapshot.selectedComponentIDs, ["a", "b"])
        XCTAssertEqual(snapshot.parts.map(\.target), [.stitchingLine, .stitchingLine])
        XCTAssertNotEqual(value.componentBrowseEpoch, oldScope)
        XCTAssertEqual(value.addPlacementDestination, .group("keep"))
        XCTAssertEqual(publications, 1)

        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertNil(value.snapshot?.componentTree.rows.first { $0.id == group.id })
        XCTAssertFalse(value.canUndo)
    }

    func testBatchStitchingEntersReusedGroupEvenWhenRolesAlreadyMatch() async throws {
        let original = try stitchingSource(reusingGroup: true)
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectComponents(["a", "b"])
        try await settle(value)
        value.componentPartRoleAction(.stitchingLoop)()
        try await settle(value)

        XCTAssertEqual(value.componentGroupBrowse?.path.map(\.id), ["g"])
        XCTAssertEqual(value.componentGroupBrowse?.children.map(\.id), ["a", "b", "unselected"])
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["a", "b"])
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }

    func testBatchStitchingRejectsRetainedBrowseScopeAndFailedSource() async throws {
        let original = try stitchingSource(reusingGroup: true)
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectComponents(["a", "b"])
        try await settle(value)
        let snapshot = try XCTUnwrap(value.snapshot)
        let retained = value.componentPartRoleAction(.stitchingLine)
        value.componentBrowseAction("g", snapshot: snapshot)()
        value.componentBrowseAction(nil, snapshot: snapshot)()
        retained()
        XCTAssertFalse(value.isWorking)
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())

        let failedSource = value.componentPartRoleAction(.stitchingLine)
        await value.load(data: Data("invalid archive".utf8))
        failedSource()
        XCTAssertFalse(value.isWorking)
        XCTAssertNil(value.componentGroupBrowse)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }

    private func stitchingSource(reusingGroup: Bool) throws -> Dust3DDocument {
        let rows =
            "<component id='a' linkDataType='partId' linkData='p'/><component id='b' linkDataType='partId' linkData='q'/>"
        let hierarchy =
            reusingGroup ? "<component id='g'>\(rows)<component id='unselected'/></component>" : rows
        let role = reusingGroup ? "target='StitchingLoop'" : ""
        let xml = """
            <canvas><nodes/><edges/><parts><part id='p' \(role)/><part id='q' \(role)/></parts>
            <components>\(hierarchy)<component id='keep'/></components></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
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
