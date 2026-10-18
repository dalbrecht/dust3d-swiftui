import Dust3DDocument
import Dust3DKit
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorMaterialPreviewTests: XCTestCase {
    func testShouldExposeRetainedAssetAndPNGFailureInTheEditorNotice() async throws {
        let document = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true)
        let baker = FailingMaterialBaker(
            error: ArchiveTextureBakingError.imageDecoding(assetName: "images/broken.png", cause: .invalidPNG))
        let store = EditorStore(materialBaker: baker)
        defer { store.stop() }
        await store.load(data: document.encoded())
        await store.generation?.value
        await store.materialGeneration?.value
        XCTAssertTrue(store.materialIssue?.contains("images/broken.png") == true)
        XCTAssertTrue(store.materialIssue?.contains("PNG") == true)
        XCTAssertNotNil(store.mesh)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
    }

    func testShouldRetainOrdinaryMeshAndOriginalMaterialFailureWithoutChangingDocument() async throws {
        let document = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true)
        let service = FailingMaterialBaker()
        let store = EditorStore(materialBaker: service)
        defer { store.stop() }
        await store.load(data: document.encoded())
        await store.generation?.value
        await store.materialGeneration?.value
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.bakedMesh)
        XCTAssertEqual(store.materialIssue, "Original material decode cause")
        XCTAssertFalse(store.isBakingMaterials)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.canSave)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        let previousCount = await service.count
        store.retryMaterials()
        await store.materialGeneration?.value
        let currentCount = await service.count
        XCTAssertEqual(currentCount, previousCount + 1)
        store.stop()
        XCTAssertNil(store.materialIssue)
        XCTAssertNil(store.bakedMesh)
    }
    func testShouldRefreshMaterialOnlyEditsWhileKeepingGeometryAndUndoLossless() async throws {
        let source = try StitchingFixture.document(loop: true, isolatedLoop: true)
        let service = FailingMaterialBaker()
        let store = EditorStore(materialBaker: service)
        defer { store.stop() }
        await store.load(data: source.encoded())
        await store.generation?.value
        await store.materialGeneration?.value
        let count = await service.count
        let geometryRevision = store.previewRevision
        store.setPartMaterial(StitchingFixture.identity(199), property: .metallic, value: "0.5")
        for _ in 0..<300 where store.isWorking { try await Task.sleep(for: .milliseconds(5)) }
        await store.materialGeneration?.value
        let editedCount = await service.count
        XCTAssertEqual(editedCount, count + 1)
        XCTAssertEqual(store.previewRevision, geometryRevision)
        XCTAssertTrue(store.canUndo)
        store.undo()
        for _ in 0..<300 where store.isWorking { try await Task.sleep(for: .milliseconds(5)) }
        await store.generation?.value
        await store.materialGeneration?.value
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
    }

    func testShouldDiscardLateBakesAcrossReplacementStopAndEmptyDocument() async throws {
        let document = try StitchingFixture.document(loop: true, isolatedLoop: true)
        let bytes = document.encoded()
        let baked = try await MeshBakingService().load(
            data: bytes, options: MeshBakeOptions(colorSize: 32, normalSize: 16, materialSize: 8, atlasTextureSize: 32))
        let service = SuspendedMaterialBaker()
        let store = EditorStore(materialBaker: service)
        defer { store.stop() }
        await store.load(data: bytes)
        await store.generation?.value
        try await waitForRequests(1, service)
        let obsolete = try XCTUnwrap(store.materialGeneration)
        await store.load(data: bytes)
        await store.generation?.value
        try await waitForRequests(2, service)
        let current = try XCTUnwrap(store.materialGeneration)
        await service.finish(1, baked)
        await current.value
        XCTAssertNotNil(store.bakedMesh)
        let revision = store.materialViewportRevision
        await service.finish(0, baked)
        await obsolete.value
        XCTAssertEqual(store.materialViewportRevision, revision)
        store.materialRenderError = "Original GPU cause"
        XCTAssertNil(store.bakedMesh)
        XCTAssertNotNil(store.mesh)
        store.retryMaterials()
        try await waitForRequests(3, service)
        let stopped = try XCTUnwrap(store.materialGeneration)
        store.stop()
        await service.finish(2, baked)
        await stopped.value
        XCTAssertNil(store.bakedMesh)
        XCTAssertNil(store.mesh)
        XCTAssertFalse(store.isBakingMaterials)
        await store.load(data: Dust3DDocument.emptyArchive())
        XCTAssertNil(store.bakedMesh)
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.materialIssue)
        let count = await service.count
        XCTAssertEqual(count, 3)
    }

    private func waitForRequests(_ expected: Int, _ service: SuspendedMaterialBaker) async throws {
        for _ in 0..<300 {
            if await service.count >= expected { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Material request was not enqueued")
    }

}

private actor FailingMaterialBaker: ArchiveTextureBaking {
    private(set) var count = 0
    private let error: any Error
    init(error: any Error = Failure.decoding) { self.error = error }
    private enum Failure: LocalizedError {
        case decoding
        var errorDescription: String? { "Original material decode cause" }
    }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        count += 1
        throw error
    }
}

private actor SuspendedMaterialBaker: ArchiveTextureBaking {
    private var pending: [CheckedContinuation<MeshWithBakedTextures, any Error>?] = []
    var count: Int { pending.count }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ index: Int, _ mesh: MeshWithBakedTextures) {
        pending[index]?.resume(returning: mesh)
        pending[index] = nil
    }
}
