import Foundation
import XCTest

@testable import Dust3DKit
@testable import Dust3DViewer

@MainActor
final class ViewerImportedMaterialTests: XCTestCase {
    private func snapshot() throws -> MeshFileSnapshot {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/ImportedSurface.ds3")
        let data = try Data(contentsOf: url)
        return MeshFileSnapshot(
            data: data, mesh: try MeshLoader.loadIndexed(data: data),
            materialSourceCapabilities: .known(hasLegacySurfaceDetails: false))
    }

    func test_should_prepare_imported_materials_and_clear_notice_only_after_current_gpu_frame() async throws {
        let snapshot = try snapshot()
        let baker = ImportedUnexpectedBaker()
        let store = ViewerStore(
            service: ImportedViewerSnapshotLoader(snapshot: snapshot), materialBaker: baker,
            importedMaterialLoader: ArchiveImportedMaterialService())
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/imported.ds3"))
        await store.loadTask?.value
        await store.materialTask?.value
        XCTAssertNotNil(store.importedMaterials)
        XCTAssertNil(store.bakedMesh)
        XCTAssertFalse(store.isBakingMaterials)
        XCTAssertTrue(store.isUpdatingMaterials)
        XCTAssertNil(store.materialIssue)
        store.materialsFailed("Obsolete GPU cause", revision: store.meshRevision + store.materialRevision - 1)
        XCTAssertNotNil(store.importedMaterials)
        XCTAssertNil(store.materialIssue)
        XCTAssertTrue(store.previewCompatibilityWarning?.contains("GLB materials") == true)
        let revision = store.meshRevision + store.materialRevision
        store.materialsRendered(revision: revision - 1)
        XCTAssertTrue(store.isUpdatingMaterials)
        XCTAssertNotNil(store.previewCompatibilityWarning)
        store.materialsRendered(revision: revision)
        XCTAssertFalse(store.isUpdatingMaterials)
        XCTAssertNil(store.previewCompatibilityWarning)
        store.materialFailed("Original imported GPU cause")
        XCTAssertNil(store.importedMaterials)
        XCTAssertNotNil(store.mesh)
        XCTAssertEqual(store.materialIssue, "Original imported GPU cause")
        XCTAssertFalse(store.isUpdatingMaterials)
        XCTAssertNotNil(store.previewCompatibilityWarning)
        let calls = await baker.calls
        XCTAssertEqual(calls, 0)
    }

    func test_should_reject_old_imported_results_after_replacement_and_stop() async throws {
        let snapshot = try snapshot()
        let prepared = try XCTUnwrap(ImportedMaterialRenderLoader.loadIfPresent(data: snapshot.data))
        let importer = SuspendedViewerImporter()
        let store = ViewerStore(
            service: ImportedViewerSnapshotLoader(snapshot: snapshot), materialBaker: ImportedUnexpectedBaker(),
            importedMaterialLoader: importer)
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/first.ds3"))
        await store.loadTask?.value
        try await waitForRequests(1, importer)
        let old = try XCTUnwrap(store.materialTask)
        store.open(URL(fileURLWithPath: "/test/second.ds3"))
        await store.loadTask?.value
        try await waitForRequests(2, importer)
        await importer.finish(1, prepared)
        await store.materialTask?.value
        let revision = store.materialRevision
        await importer.finish(0, prepared)
        await old.value
        XCTAssertEqual(store.materialRevision, revision)
        XCTAssertNotNil(store.importedMaterials)
        XCTAssertEqual(store.documentName, "second.ds3")
        store.retryMaterials()
        try await waitForRequests(3, importer)
        let stopped = try XCTUnwrap(store.materialTask)
        store.stop()
        await importer.finish(2, prepared)
        await stopped.value
        XCTAssertNil(store.importedMaterials)
        XCTAssertNil(store.mesh)
        XCTAssertFalse(store.isBakingMaterials)
    }

    func test_should_preserve_decode_cause_and_retry_exact_snapshot_without_losing_geometry() async throws {
        let snapshot = try snapshot()
        let importer = SuspendedViewerImporter()
        let store = ViewerStore(
            service: ImportedViewerSnapshotLoader(snapshot: snapshot), materialBaker: ImportedUnexpectedBaker(),
            importedMaterialLoader: importer)
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/imported.ds3"))
        await store.loadTask?.value
        try await waitForRequests(1, importer)
        await importer.fail(0, error: MeshJPEGDecodingError.unsupportedPixelLayout)
        await store.materialTask?.value
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.importedMaterials)
        XCTAssertEqual(store.materialIssue, "The JPEG pixel layout is not supported.")
        store.retryMaterials()
        try await waitForRequests(2, importer)
        let inputs = await importer.inputs
        XCTAssertEqual(inputs, [snapshot.data, snapshot.data])
        await importer.fail(1, error: CancellationError())
        await store.materialTask?.value
        XCTAssertFalse(store.isBakingMaterials)
        XCTAssertNotNil(store.materialIssue)
    }

    private func waitForRequests(_ count: Int, _ importer: SuspendedViewerImporter) async throws {
        for _ in 0..<300 {
            if await importer.inputs.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Imported preparation was not enqueued")
    }
}

private actor ImportedViewerSnapshotLoader: MeshFileSnapshotLoading {
    let snapshot: MeshFileSnapshot
    init(snapshot: MeshFileSnapshot) { self.snapshot = snapshot }
    func loadIndexedSnapshot(url: URL) async throws -> MeshFileSnapshot { snapshot }
}
private actor ImportedUnexpectedBaker: ArchiveTextureBaking {
    private(set) var calls = 0
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        calls += 1
        throw ImportedMaterialRenderError.invalidLimits
    }
}
private actor SuspendedViewerImporter: ArchiveImportedMaterialLoading {
    private(set) var inputs: [Data] = []
    private var pending: [CheckedContinuation<ImportedMaterialRenderData?, any Error>?] = []
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        inputs.append(data)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ index: Int, _ value: ImportedMaterialRenderData?) {
        pending[index]?.resume(returning: value)
        pending[index] = nil
    }
    func fail(_ index: Int, error: any Error) {
        pending[index]?.resume(throwing: error)
        pending[index] = nil
    }
}
