import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct SidebarOrderNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class ComponentSidebarOrderTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='z' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes>
                <edges/><parts><part id='p'/></parts><components>
                <component id='a' linkDataType='partId' linkData='p'/>
                <component id='group'><component id='first'/><opaque key='retained'/><component id='middle'/><component id='last'/></component>
                <component id='c'/>
                </components></canvas>
                """.utf8))
    }

    private func makeStore() -> EditorStore {
        let stub = SidebarOrderNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Sidebar reorder did not settle")
    }

    func testExplicitNestedRowMovesWithoutRetargetingOrChangingSelectionAndUndoesExactly() async throws {
        let original = try source().encoded()
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: original)
        try await settle(store)
        store.select("z")
        try await settle(store)

        let target = try XCTUnwrap(
            ComponentPlacementTarget(snapshot: try XCTUnwrap(store.snapshot), singleComponentID: "middle"))
        for move in ComponentOrderMove.allCases {
            XCTAssertTrue(
                store.canReorderSidebarComponent(move, target: target, scopeEpoch: store.componentBrowseEpoch))
        }
        XCTAssertTrue(store.reorderSidebarComponent(.last, target: target, scopeEpoch: store.componentBrowseEpoch))
        try await settle(store)
        let edited = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(edited.componentTree.rows.map(\.id), ["a", "group", "first", "last", "middle", "c"])
        XCTAssertEqual(edited.selectedIDs, ["z"])
        XCTAssertTrue(edited.selectedComponentIDs.isEmpty)
        XCTAssertTrue(String(decoding: edited.document.modelXML, as: UTF8.self).contains("retained"))
        XCTAssertFalse(store.reorderSidebarComponent(.up, target: target, scopeEpoch: store.componentBrowseEpoch))
        let boundary = try XCTUnwrap(ComponentPlacementTarget(snapshot: edited, singleComponentID: "middle"))
        XCTAssertFalse(
            store.canReorderSidebarComponent(.down, target: boundary, scopeEpoch: store.componentBrowseEpoch))
        XCTAssertFalse(
            store.canReorderSidebarComponent(.last, target: boundary, scopeEpoch: store.componentBrowseEpoch))
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testSelectedSiblingBlockMovesDownInOneUndoAndRejectsMixedParents() async throws {
        let original = try source().encoded()
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: original)
        try await settle(store)

        store.selectComponents(["a", "middle"])
        try await settle(store)
        let mixed = try XCTUnwrap(ComponentPlacementTarget(snapshot: try XCTUnwrap(store.snapshot)))
        for move in ComponentOrderMove.allCases {
            XCTAssertFalse(
                store.canReorderSidebarComponent(move, target: mixed, scopeEpoch: store.componentBrowseEpoch))
        }

        store.selectComponents(["first", "middle"])
        try await settle(store)
        let target = try XCTUnwrap(ComponentPlacementTarget(snapshot: try XCTUnwrap(store.snapshot)))
        let epoch = store.componentBrowseEpoch
        XCTAssertFalse(store.canReorderSidebarComponent(.up, target: target, scopeEpoch: epoch))
        XCTAssertTrue(store.canReorderSidebarComponent(.down, target: target, scopeEpoch: epoch))
        XCTAssertTrue(store.reorderSidebarComponent(.down, target: target, scopeEpoch: epoch))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentTree.rows.map(\.id), ["a", "group", "last", "first", "middle", "c"])
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, ["first", "middle"])
        XCTAssertFalse(store.reorderSidebarComponent(.up, target: target, scopeEpoch: epoch))

        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testNoncontiguousSiblingsCanMoveToTopOrBottomAtBothBoundaries() async throws {
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: try source().encoded())
        try await settle(store)
        store.selectComponents(["first", "last"])
        try await settle(store)

        let target = try XCTUnwrap(ComponentPlacementTarget(snapshot: try XCTUnwrap(store.snapshot)))
        let epoch = store.componentBrowseEpoch
        XCTAssertFalse(store.canReorderSidebarComponent(.up, target: target, scopeEpoch: epoch))
        XCTAssertFalse(store.canReorderSidebarComponent(.down, target: target, scopeEpoch: epoch))
        XCTAssertTrue(store.canReorderSidebarComponent(.first, target: target, scopeEpoch: epoch))
        XCTAssertTrue(store.canReorderSidebarComponent(.last, target: target, scopeEpoch: epoch))
        XCTAssertTrue(store.reorderSidebarComponent(.first, target: target, scopeEpoch: epoch))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentTree.rows.map(\.id), ["a", "group", "first", "last", "middle", "c"])
    }

    func testRetainedRootTargetRejectsSelectionABAAndFailedSource() async throws {
        let original = try source().encoded()
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: original)
        try await settle(store)
        let originalSnapshot = try XCTUnwrap(store.snapshot)
        let originalTarget = try XCTUnwrap(
            ComponentPlacementTarget(snapshot: originalSnapshot, singleComponentID: "a"))
        XCTAssertFalse(
            store.canReorderSidebarComponent(.first, target: originalTarget, scopeEpoch: store.componentBrowseEpoch))
        XCTAssertFalse(
            store.canReorderSidebarComponent(.up, target: originalTarget, scopeEpoch: store.componentBrowseEpoch))
        XCTAssertTrue(
            store.canReorderSidebarComponent(.down, target: originalTarget, scopeEpoch: store.componentBrowseEpoch))
        store.selectComponent("c")
        try await settle(store)
        store.clearComponentSelection()
        try await settle(store)
        XCTAssertFalse(
            store.reorderSidebarComponent(.down, target: originalTarget, scopeEpoch: store.componentBrowseEpoch))

        let current = try XCTUnwrap(
            ComponentPlacementTarget(snapshot: try XCTUnwrap(store.snapshot), singleComponentID: "a"))
        XCTAssertTrue(store.canReorderSidebarComponent(.down, target: current, scopeEpoch: store.componentBrowseEpoch))
        await store.load(data: Data("broken".utf8))
        XCTAssertFalse(store.reorderSidebarComponent(.down, target: current, scopeEpoch: store.componentBrowseEpoch))
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testRetainedReorderRejectsRetiredBrowseScopeWithoutASelectionChange() async throws {
        let original = try source().encoded()
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: original)
        try await settle(store)
        let snapshot = try XCTUnwrap(store.snapshot)
        let target = try XCTUnwrap(ComponentPlacementTarget(snapshot: snapshot, singleComponentID: "middle"))
        let fullTreeEpoch = store.componentBrowseEpoch
        XCTAssertTrue(store.canReorderSidebarComponent(.up, target: target, scopeEpoch: fullTreeEpoch))

        store.componentBrowseAction("group", snapshot: snapshot)()
        XCTAssertEqual(store.componentGroupBrowse?.path.map(\.id), ["group"])
        XCTAssertTrue(target.isCurrent(in: try XCTUnwrap(store.snapshot)))
        XCTAssertFalse(store.canReorderSidebarComponent(.up, target: target, scopeEpoch: fullTreeEpoch))
        XCTAssertFalse(store.reorderSidebarComponent(.up, target: target, scopeEpoch: fullTreeEpoch))
        XCTAssertTrue(store.canReorderSidebarComponent(.up, target: target, scopeEpoch: store.componentBrowseEpoch))
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }
}
