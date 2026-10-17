import Dust3DDocument
import Dust3DKit
import XCTest
import simd

@testable import Dust3DEditor

final class PartLoopInteriorStoreTests: XCTestCase {
    private let partID = StitchingFixture.identity(100)
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Loop-interior edit or generation did not settle")
    }
    func testIsolatedLoopFillChangesActualFiniteGeometryWithoutChangingSourceGraph() throws {
        let original = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true)
        let baseline = try MeshLoader.load(data: original.encoded())
        let changed = try original.applying(.setPartFillLoopInterior(id: partID, value: false))
        let mesh = try MeshLoader.load(data: changed.encoded())
        XCTAssertGreaterThan(baseline.triangleCount, 0)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        XCTAssertNotEqual(mesh.vertices.map(\.position), baseline.vertices.map(\.position))
        XCTAssertTrue(
            mesh.vertices.allSatisfy {
                $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
                    && abs(simd_length($0.normal) - 1) < 0.0001
            })
        XCTAssertEqual(try changed.editorContents().nodes, try original.editorContents().nodes)
        XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
    }
    func testConnectedLoopFillFlagDoesNotChangeTheExistingStitchedSurface() throws {
        let original = try StitchingFixture.document(loop: true, attributes: "")
        let changed = try original.applying(.setPartFillLoopInterior(id: StitchingFixture.identity(101), value: false))
        XCTAssertEqual(
            try MeshLoader.load(data: changed.encoded()).vertices.map(\.position),
            try MeshLoader.load(data: original.encoded()).vertices.map(\.position))
        XCTAssertEqual(
            try changed.editorContents().parts.first(where: { $0.id == StitchingFixture.identity(101) })?
                .isLoopInteriorFilled, false)
    }
    func testOptionalMeshLoadingRecognizesOnlySuccessfulEmptyAndPreservesRealErrors() throws {
        let original = try StitchingFixture.document(
            loop: true, attributes: "", isolatedLoop: true,
            includeUncombinedModel: false)
        XCTAssertNotNil(try MeshLoader.loadIfPresent(data: original.encoded()))
        let unfilled = try original.applying(.setPartFillLoopInterior(id: partID, value: false))
        XCTAssertNil(try MeshLoader.loadIfPresent(data: unfilled.encoded()))
        XCTAssertThrowsError(try MeshLoader.load(data: unfilled.encoded())) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 5)
            XCTAssertFalse(($0 as? MeshLoadingError)?.message.isEmpty ?? true)
        }
        let straight = try StitchingFixture.document(loop: false, degenerateStraight: true)
        XCTAssertNotNil(try MeshLoader.loadIfPresent(data: straight.encoded()))
        let failed = try WrappingFixture.document(mode: "Cloth", attributes: "wrapFaces='64' wrapOffset='-1'")
        XCTAssertThrowsError(try MeshLoader.loadIfPresent(data: failed.encoded())) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 3)
            XCTAssertFalse(($0 as? MeshLoadingError)?.message.isEmpty ?? true)
        }
        XCTAssertThrowsError(try MeshLoader.loadIfPresent(data: Data([0, 1, 2]))) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
        }
    }
    @MainActor func testGenuineGenerationFailureRetainsPreviousMeshAndDiagnosticAsStale() async throws {
        let original = try WrappingFixture.document(attributes: "wrapFaces='64' wrapOffset='-1'")
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        let baseline = try XCTUnwrap(store.mesh)
        store.setComponentWrapMode(WrappingFixture.groupID, mode: .cloth)
        try await settle(store)
        XCTAssertNotNil(store.previewState.errorMessage)
        XCTAssertTrue(store.previewState.isStale)
        XCTAssertEqual(store.mesh?.vertices.map(\.position), baseline.vertices.map(\.position))
    }
    @MainActor func testDisablingOnlyIsolatedLoopFillClearsPreviewAndUndoRedoRestoresIt() async throws {
        let original = try StitchingFixture.document(
            loop: true, attributes: "", isolatedLoop: true,
            includeUncombinedModel: false)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        let baseline = try XCTUnwrap(store.mesh)
        XCTAssertGreaterThan(baseline.triangleCount, 0)
        store.selectPart(partID)
        try await settle(store)
        let camera = store.cameraReset
        store.setPartFillLoopInterior(partID, value: false)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedPart?.isLoopInteriorFilled, false)
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertFalse(store.previewState.isStale)
        XCTAssertFalse(store.isGenerating)
        XCTAssertEqual(store.snapshot?.selectedPartID, partID)
        XCTAssertEqual(store.cameraReset, camera)
        let changed = try XCTUnwrap(store.snapshot?.document.encoded())
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(store.mesh?.vertices.map(\.position), baseline.vertices.map(\.position))
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertFalse(store.previewState.isStale)
    }
    @MainActor func testControllerRetainsCameraSelectionExactHistoryAndNoopRedo() async throws {
        let original = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true)
        let store = EditorStore()
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: original.encoded())
        try await settle(store)
        let baseline = try XCTUnwrap(store.mesh)
        store.selectPart(partID)
        try await settle(store)
        let camera = store.cameraReset
        store.setPartFillLoopInterior(partID, value: false)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        let mesh = try XCTUnwrap(store.mesh)
        XCTAssertNotEqual(mesh.vertices.map(\.position), baseline.vertices.map(\.position))
        XCTAssertEqual(store.snapshot?.selectedPart?.isLoopInteriorFilled, false)
        XCTAssertEqual(store.snapshot?.selectedPartID, partID)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(publications, 1)
        let changed = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertEqual(
            try Dust3DDocument(data: changed).editorContents().parts.first(where: { $0.id == partID })?
                .isLoopInteriorFilled, false)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        let revision = store.previewRevision
        store.setPartFillLoopInterior(partID, value: true)
        try await settle(store)
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertTrue(store.canRedo)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
        XCTAssertEqual(store.mesh?.vertices.map(\.position), mesh.vertices.map(\.position))
        let count = publications
        store.setPartFillLoopInterior("missing", value: true)
        try await settle(store)
        XCTAssertTrue(store.errorMessage?.contains("not present") == true)
        XCTAssertEqual(publications, count)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
    }
}
