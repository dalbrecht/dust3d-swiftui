import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct AddProfileTransferNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class AddProfileTransferStoreTests: XCTestCase {
    func testDualProfileSwitchRejectsOldCallbacksAndWaitsForFreshPointer() async throws {
        let source = Dust3DDocument.emptyArchive()
        let stub = AddProfileTransferNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: source)
        let before = try XCTUnwrap(store.snapshot)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }

        store.setDualCanvasProfile(true)
        let frontLease = store.canvasProfiles.lease
        let front = CanvasProjection(bounds: store.bounds, plane: .front, width: 420, height: 240)
        store.setCanvasContext(projection: front, width: 420, height: 240, lease: frontLease)
        store.beginAddMode()
        let frontMode = store.addModeID
        let frontPoint = CanvasPoint(x: 210, y: 120)
        store.updateAddPointer(at: frontPoint, modeID: frontMode)
        XCTAssertTrue(store.canPlaceAddGhost)

        store.plane = .side
        let sideLease = store.canvasProfiles.lease
        let sideMode = store.addModeID
        XCTAssertNotEqual(sideLease, frontLease)
        XCTAssertNotEqual(sideMode, frontMode)
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertNil(store.frozenAddProjection)
        XCTAssertNil(store.addGhostPoint)
        XCTAssertFalse(store.canPlaceAddGhost)

        store.setCanvasContext(projection: front, width: 420, height: 240, lease: frontLease)
        store.releaseCanvasProfile(lease: frontLease)
        store.updateAddPointer(at: frontPoint, modeID: frontMode)
        store.placeAddNode(at: frontPoint, modeID: frontMode)
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertNil(store.frozenAddProjection)
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(store.canPlaceAddGhost)

        let side = CanvasProjection(bounds: store.bounds, plane: .side, width: 350, height: 180)
        store.setCanvasContext(projection: side, width: 350, height: 180, lease: sideLease)
        XCTAssertEqual(store.frozenAddProjection?.plane, .side)
        XCTAssertEqual(store.canvasHeight, 180)
        XCTAssertFalse(store.canPlaceAddGhost)
        store.updateAddPointer(at: frontPoint, modeID: frontMode)
        XCTAssertNil(store.addGhostPoint)
        let sidePoint = CanvasPoint(x: 190, y: 105)
        store.updateAddPointer(at: sidePoint, modeID: sideMode)
        XCTAssertEqual(store.addGhostPoint, sidePoint)
        XCTAssertTrue(store.canPlaceAddGhost)
        store.placeAddNode(at: frontPoint, modeID: frontMode)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.addGhostPoint, sidePoint)

        let after = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(after.document.encoded(), before.document.encoded())
        XCTAssertEqual(after.documentRevision, before.documentRevision)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(publications, 0)

        let expected = try side.position(at: sidePoint, hiddenCoordinate: before.origin?.x ?? 0.5)
        store.placeAddNode(at: sidePoint, modeID: sideMode)
        try await settle(store)
        let position = try XCTUnwrap(store.snapshot?.nodes.first?.value.position)
        XCTAssertEqual(position.x, expected.x, accuracy: 1e-12)
        XCTAssertEqual(position.y, expected.y, accuracy: 1e-12)
        XCTAssertEqual(position.z, expected.z, accuracy: 1e-12)
        XCTAssertEqual(publications, 1)
        XCTAssertTrue(store.canUndo)

        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), before.document.encoded())
        XCTAssertFalse(store.canUndo)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Placement did not settle")
    }
}
