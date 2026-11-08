import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class NodeInspectorOwnershipTests: XCTestCase {
    func testRetainedResetAndApplyCannotUseAnotherNodesDraft() async throws {
        let store = makeStore()
        defer { store.stop() }
        let bytes = try capsule()
        await store.load(data: bytes)
        let nodes = try XCTUnwrap(store.snapshot?.nodes)
        store.select(nodes[0].id)
        try await settle(store)
        let first = try XCTUnwrap(store.inspectorNodeDraftSource)
        let draft = InspectorNodeDraft()
        draft.synchronize(to: first)
        draft.x = 0.8125
        let old = try XCTUnwrap(store.nodeInspectorActions(source: first, draft: draft))

        store.select(nodes[1].id)
        try await settle(store)
        let second = try XCTUnwrap(store.inspectorNodeDraftSource)
        let current = try XCTUnwrap(store.nodeInspectorActions(source: second, draft: draft))
        current.reset()
        current.apply()
        XCTAssertEqual(draft.x, 0.8125)
        XCTAssertEqual(draft.source, first)
        XCTAssertFalse(store.isWorking)

        draft.synchronize(to: second)
        draft.x = 0.625
        old.reset()
        old.apply()
        try await settle(store)
        XCTAssertEqual(draft.x, 0.625)
        XCTAssertEqual(store.snapshot?.selectedID, nodes[1].id)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        XCTAssertFalse(store.canUndo)
    }

    func testSameIDReplacementAndLockRoundTripRejectRetainedActionsThenFreshEditReopens() async throws {
        let store = makeStore()
        defer { store.stop() }
        let bytes = try capsule()
        await store.load(data: bytes)
        let node = try XCTUnwrap(store.snapshot?.nodes.first)
        store.select(node.id)
        try await settle(store)
        let original = try XCTUnwrap(store.inspectorNodeDraftSource)
        let draft = InspectorNodeDraft()
        draft.synchronize(to: original)
        let old = try XCTUnwrap(store.nodeInspectorActions(source: original, draft: draft))

        await store.load(data: bytes)
        store.select(node.id)
        try await settle(store)
        let replacement = try XCTUnwrap(store.inspectorNodeDraftSource)
        draft.synchronize(to: replacement)
        draft.x = 0.75
        old.reset()
        old.apply()
        XCTAssertEqual(draft.x, 0.75)
        XCTAssertFalse(store.isWorking)

        let locked = try XCTUnwrap(store.nodeInspectorActions(source: replacement, draft: draft))
        store.setLock(.x, isLocked: true)
        try await settle(store)
        store.setLock(.x, isLocked: false)
        try await settle(store)
        locked.reset()
        locked.apply()
        XCTAssertEqual(draft.x, 0.75)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)

        let fresh = try XCTUnwrap(store.nodeInspectorActions(source: replacement, draft: draft))
        fresh.apply()
        try await settle(store)
        let edited = try XCTUnwrap(store.snapshot?.document)
        XCTAssertEqual(try edited.node(id: node.id).position.x, 0.75)
        XCTAssertTrue(store.canUndo)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Edited Capsule.ds3")
        let files = DocumentFileService()
        try await files.save(edited, to: url)
        let reopened = try await files.load(from: url)
        XCTAssertEqual(reopened.encoded(), edited.encoded())
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        XCTAssertFalse(store.canUndo)
    }

    func testActorRejectsRetainedNodeEditAfterSelectionRoundTrip() async throws {
        let session = EditorSession()
        let bytes = try capsule()
        let opened = try await session.open(data: bytes)
        let node = try XCTUnwrap(opened.nodes.first)
        let other = try XCTUnwrap(opened.nodes.last)
        let selected = try await session.select(node.id)
        let target = CanvasAdjustmentTarget(snapshot: selected)
        _ = try await session.select(other.id)
        let current = try await session.select(node.id)
        do {
            _ = try await session.editInspectorNode(
                id: node.id, position: .init(x: 0.75, y: 0.5, z: 1), radius: 0.2, target: target)
            XCTFail("Selection round trip must retire the captured node edit")
        } catch { XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment) }

        let fresh = try await session.editInspectorNode(
            id: node.id, position: .init(x: 0.75, y: 0.5, z: 1), radius: 0.2,
            target: CanvasAdjustmentTarget(snapshot: current))
        XCTAssertEqual(fresh.selectedID, node.id)
        XCTAssertTrue(fresh.canUndo)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), bytes)
        XCTAssertFalse(undone.canUndo)
    }

    private func capsule() throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/Capsule.ds3")
        return try Data(contentsOf: url)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Editor operation did not settle")
    }

    private func makeStore() -> EditorStore {
        let stub = NodeInspectorNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }
}

private struct NodeInspectorNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading
{
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        throw CancellationError()
    }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    { throw CancellationError() }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}
