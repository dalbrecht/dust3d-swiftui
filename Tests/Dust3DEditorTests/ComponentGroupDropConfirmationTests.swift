import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct GroupDropNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class ComponentGroupDropConfirmationTests: XCTestCase {
    private func setup() async throws -> (EditorStore, Data) {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><components>
                <component id='a' name='First'/>
                <component id='b' name='Second'/>
                <component id='g' name='Destination'><component id='child'/></component>
                <component id='other' name='Other'/>
                </components></canvas>
                """.utf8)
        ).encoded()
        let stub = GroupDropNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
        await store.load(data: original)
        return (store, original)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Component drop did not settle")
    }

    func testGroupDropStagesThenMovesExactBlockWithOneUndo() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        store.selectComponents(["a", "b"])
        try await settle(store)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        let token = try XCTUnwrap(store.beginComponentDrag(grabbedID: "b"))
        XCTAssertTrue(store.dropComponents(token: token, in: .component("g")))
        let proposed = try XCTUnwrap(store.pendingComponentGroupDrop)
        XCTAssertEqual(proposed.destinationTitle, "Destination")
        XCTAssertEqual(proposed.componentCount, 2)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(store.dropComponents(token: token, in: .component("other")))
        XCTAssertTrue(store.confirmComponentGroupDrop(proposed.id))
        XCTAssertFalse(store.confirmComponentGroupDrop(proposed.id))
        try await settle(store)
        XCTAssertNil(store.pendingComponentGroupDrop)
        XCTAssertEqual(
            store.snapshot?.componentTree.rows.map(\.id), ["g", "child", "a", "b", "other"])
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, ["a", "b"])
        XCTAssertEqual(publications, 1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testCancelDoesNotReorderAndBeforeAfterAndRootStayImmediate() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        let groupToken = try XCTUnwrap(store.beginComponentDrag(grabbedID: "a"))
        XCTAssertTrue(store.dropComponents(token: groupToken, in: .component("g")))
        let proposed = try XCTUnwrap(store.pendingComponentGroupDrop)
        store.cancelComponentGroupDrop(proposed.id)
        XCTAssertNil(store.pendingComponentGroupDrop)
        XCTAssertFalse(store.confirmComponentGroupDrop(proposed.id))
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)

        let reorderToken = try XCTUnwrap(store.beginComponentDrag(grabbedID: "a"))
        XCTAssertTrue(store.dropComponents(token: reorderToken, at: .after("b")))
        try await settle(store)
        XCTAssertNil(store.pendingComponentGroupDrop)
        XCTAssertEqual(store.snapshot?.componentTree.rows.prefix(2).map(\.id), ["b", "a"])
        let rootToken = try XCTUnwrap(store.beginComponentDrag(grabbedID: "child"))
        XCTAssertTrue(store.dropComponents(token: rootToken, in: .root))
        try await settle(store)
        XCTAssertNil(store.pendingComponentGroupDrop)
        XCTAssertNil(store.snapshot?.componentTree.rows.first { $0.id == "child" }?.component.parentID)
    }

    func testStaleSelectionScopeAndSourceCannotCommitOrCancelNewerProposal() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        func stage(in destination: String) throws -> UUID {
            let token = try XCTUnwrap(store.beginComponentDrag(grabbedID: "a"))
            XCTAssertTrue(store.dropComponents(token: token, in: .component(destination)))
            return try XCTUnwrap(store.pendingComponentGroupDrop?.id)
        }
        let first = try stage(in: "g")
        let next = try stage(in: "other")
        store.cancelComponentGroupDrop(first)
        XCTAssertFalse(store.confirmComponentGroupDrop(first))
        XCTAssertEqual(store.pendingComponentGroupDrop?.id, next)

        store.selectComponent("b")
        try await settle(store)
        store.selectComponent(nil)
        try await settle(store)
        XCTAssertFalse(store.confirmComponentGroupDrop(next))
        let beforeBrowse = try stage(in: "g")
        store.componentBrowseAction("g", snapshot: try XCTUnwrap(store.snapshot))()
        XCTAssertNil(store.pendingComponentGroupDrop)
        XCTAssertFalse(store.confirmComponentGroupDrop(beforeBrowse))
        let beforeFailure = try stage(in: "other")
        await store.load(data: Data("invalid archive".utf8))
        XCTAssertFalse(store.confirmComponentGroupDrop(beforeFailure))
        XCTAssertNil(store.pendingComponentGroupDrop)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }
}
