import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct DirectOriginNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class DirectOriginDragStoreTests: XCTestCase {
    private func setup() async throws -> (EditorStore, Data) {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas originX='.5' originY='.6' originZ='.7'>
                <nodes><node id='n' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes>
                <parts><part id='p'/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components>
                </canvas>
                """.utf8)
        ).encoded()
        let stub = DirectOriginNoNative()
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
        XCTFail("Origin drag did not settle")
    }

    private func installCanvas(_ store: EditorStore, lease: UUID? = nil) -> CanvasProjection {
        let projection = CanvasProjection(bounds: store.bounds, plane: store.plane, width: 420, height: 300)
        store.setCanvasContext(projection: projection, width: 420, height: 300, lease: lease)
        store.setReferenceColorCanvasContext(projection: projection, width: 420, height: 300)
        return projection
    }

    func testOrdinaryOriginDragPreviewsAndCommitsOnceWithoutChangingToolOrPicks() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        store.select("n")
        try await settle(store)
        store.setLock(.x, isLocked: true)
        try await settle(store)
        let projection = installCanvas(store)
        let begin = try XCTUnwrap(store.directOriginDragAction(projection: projection, lease: nil))
        let token = UUID()
        let before = try XCTUnwrap(store.snapshot?.origin)
        let delta = CanvasPoint(x: 14, y: 19)
        begin(token)
        store.updateOriginDrag(token: token, translation: delta)
        let preview = try XCTUnwrap(store.originDragPosition)
        XCTAssertEqual(preview.x, before.x)
        XCTAssertEqual(preview.z, before.z)
        XCTAssertEqual(preview.y, before.y + delta.y / projection.scale, accuracy: 1e-12)
        XCTAssertFalse(store.isMovingOrigin)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["n"])
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
        store.finishOriginDrag(token: token, translation: delta)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin?.y ?? 0, preview.y, accuracy: 1e-12)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["n"])
        XCTAssertNil(store.originDragPosition)
        XCTAssertFalse(store.isMovingOrigin)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testDirectCancelAndStalePaneToolAndFailedSourceDoNotRetarget() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        store.setDualCanvasProfile(true)
        let frontLease = store.canvasProfiles.lease
        let front = installCanvas(store, lease: frontLease)
        let old = try XCTUnwrap(store.directOriginDragAction(projection: front, lease: frontLease))
        let frontToken = UUID()
        old(frontToken)
        store.updateOriginDrag(token: frontToken, translation: .init(x: 12, y: 9))
        XCTAssertNotNil(store.originDragPosition)
        store.cancelOriginDrag(token: frontToken)
        XCTAssertNil(store.originDragPosition)
        XCTAssertFalse(store.canUndo)

        let sideLease = try XCTUnwrap(store.activateCanvasCompanion(plane: .side, expectedLease: frontLease))
        let side = installCanvas(store, lease: sideLease)
        old(frontToken)
        store.updateOriginDrag(token: frontToken, translation: .init(x: 12, y: 9))
        XCTAssertNil(store.originDragPosition)
        let direct = try XCTUnwrap(store.directOriginDragAction(projection: side, lease: sideLease))
        let sideToken = UUID()
        direct(sideToken)
        store.updateOriginDrag(token: sideToken, translation: .init(x: 15, y: 0))
        let preview = try XCTUnwrap(store.originDragPosition)
        XCTAssertEqual(preview.x, 0.5)
        XCTAssertEqual(preview.y, 0.6)
        XCTAssertEqual(preview.z, 0.7 + 15 / side.scale, accuracy: 1e-12)

        store.beginAddMode()
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertNil(store.directOriginDragAction(projection: side, lease: sideLease))
        store.finishOriginDrag(token: sideToken, translation: .init(x: 15, y: 0))
        store.cancelAddMode()
        let current = installCanvas(store, lease: sideLease)
        store.setRigEdgeSelection(true)
        XCTAssertNil(store.directOriginDragAction(projection: current, lease: sideLease))
        store.setRigEdgeSelection(false)
        let fresh = try XCTUnwrap(store.directOriginDragAction(projection: current, lease: sideLease))
        await store.load(data: Data("invalid archive".utf8))
        fresh(sideToken)
        store.finishOriginDrag(token: sideToken, translation: .init(x: 15, y: 0))
        XCTAssertNil(store.originDragPosition)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }
    func testActorRejectsRetainedOriginBaselineAfterFailedReplacement() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        let session = EditorSession()
        let before = try await session.open(data: original)
        let projection = CanvasProjection(bounds: .init(nodes: before.nodes), plane: .front, width: 420, height: 300)
        let baseline = try OriginDrag(snapshot: before, projection: projection)
        do {
            _ = try await session.open(data: Data("invalid archive".utf8))
            XCTFail("Invalid archive opened")
        } catch {}
        do {
            _ = try await session.commitOriginDrag(baseline, translation: .init(x: 10, y: 12))
            XCTFail("Failed replacement retained a writable origin target")
        } catch { XCTAssertEqual(error as? EditorError, .staleOriginDrag) }
        let retained = try await session.animationSnapshot().editor
        XCTAssertEqual(retained.document.encoded(), original)
        XCTAssertFalse(retained.canUndo)
    }

}
