import Dust3DDocument
import Dust3DKit
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorImportedMaterialTests: XCTestCase {
    private func source() throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/ImportedSurface.ds3")
        return try Data(contentsOf: url)
    }

    func test_should_present_imported_materials_only_for_the_current_gpu_frame() async throws {
        let bytes = try source()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: bytes)
        await store.generation?.value
        await store.materialGeneration?.value
        XCTAssertNil(store.errorMessage)
        XCTAssertNotNil(store.mesh)
        XCTAssertNotNil(store.importedMaterials)
        XCTAssertNil(store.bakedMesh)
        XCTAssertFalse(store.isBakingMaterials)
        XCTAssertTrue(store.isUpdatingMaterials)
        XCTAssertNotNil(store.previewCompatibilityWarning)
        let revision = store.materialViewportRevision
        store.materialsRendered(revision: revision - 1)
        XCTAssertTrue(store.isUpdatingMaterials)
        store.materialsFailed("Obsolete GPU cause", revision: revision - 1)
        XCTAssertNil(store.materialIssue)
        store.materialsRendered(revision: revision)
        XCTAssertFalse(store.isUpdatingMaterials)
        XCTAssertNil(store.previewCompatibilityWarning)
        store.materialsFailed("Original GPU cause", revision: revision)
        XCTAssertNil(store.importedMaterials)
        XCTAssertNotNil(store.mesh)
        XCTAssertFalse(store.isUpdatingMaterials)
        XCTAssertEqual(store.materialIssue, "Original GPU cause")
        XCTAssertNotNil(store.previewCompatibilityWarning)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        store.retryMaterials()
        await store.materialGeneration?.value
        XCTAssertNotNil(store.importedMaterials)
        XCTAssertNil(store.materialIssue)
    }

    func test_should_preserve_imported_assets_through_edit_undo_redo_and_save_reopen() async throws {
        let bytes = try source()
        let original = try Dust3DDocument(data: bytes)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: bytes)
        await settle(store)
        let node = try XCTUnwrap(store.snapshot?.nodes.first)
        var saved: Data?
        store.onDocumentChanged = { saved = $0 }
        store.move(
            id: node.id,
            to: NodePosition(x: node.value.position.x + 0.1, y: node.value.position.y, z: node.value.position.z))
        await settle(store)
        XCTAssertTrue(store.canUndo)
        XCTAssertNotNil(store.importedMaterials)
        XCTAssertNil(store.errorMessage)
        let edited = try XCTUnwrap(saved)
        XCTAssertNotEqual(edited, bytes)
        let asset = "models/{00000300-0000-4000-8000-000000000300}.glb"
        XCTAssertEqual(try Dust3DDocument(data: edited).asset(named: asset), original.asset(named: asset))
        store.undo()
        await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        XCTAssertNotNil(store.importedMaterials)
        store.redo()
        await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), edited)
        let reopened = EditorStore()
        defer { reopened.stop() }
        await reopened.load(data: edited)
        await settle(reopened)
        XCTAssertNotNil(reopened.importedMaterials)
        XCTAssertEqual(reopened.snapshot?.document.asset(named: asset), original.asset(named: asset))
    }

    func test_should_reject_obsolete_imported_results_across_replacement_stop_and_empty_output() async throws {
        let bytes = try source()
        let prepared = try XCTUnwrap(ImportedMaterialRenderLoader.loadIfPresent(data: bytes))
        let importer = SuspendedEditorImporter()
        let store = EditorStore(importedMaterialLoader: importer)
        defer { store.stop() }
        await store.load(data: bytes)
        await store.generation?.value
        try await requests(1, importer)
        let obsolete = try XCTUnwrap(store.materialGeneration)
        await store.load(data: bytes)
        await store.generation?.value
        try await requests(2, importer)
        await importer.finish(1, prepared)
        await store.materialGeneration?.value
        let revision = store.materialViewportRevision
        await importer.fail(0, MeshJPEGDecodingError.unsupportedPixelLayout)
        await obsolete.value
        XCTAssertEqual(store.materialViewportRevision, revision)
        XCTAssertNotNil(store.importedMaterials)
        XCTAssertNil(store.materialIssue)
        store.retryMaterials()
        try await requests(3, importer)
        let stopped = try XCTUnwrap(store.materialGeneration)
        store.stop()
        await importer.finish(2, prepared)
        await stopped.value
        XCTAssertNil(store.importedMaterials)
        XCTAssertFalse(store.isUpdatingMaterials)
        await store.load(data: Dust3DDocument.emptyArchive())
        await store.generation?.value
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.importedMaterials)
        XCTAssertNil(store.materialIssue)
        let inputs = await importer.inputs
        XCTAssertEqual(inputs.count, 3)
    }

    func test_should_keep_decode_cause_geometry_and_exact_retry_snapshot() async throws {
        let bytes = try source()
        let importer = SuspendedEditorImporter()
        let store = EditorStore(importedMaterialLoader: importer)
        defer { store.stop() }
        await store.load(data: bytes)
        await store.generation?.value
        try await requests(1, importer)
        await importer.fail(0, MeshJPEGDecodingError.unsupportedPixelLayout)
        await store.materialGeneration?.value
        XCTAssertEqual(store.materialIssue, "The JPEG pixel layout is not supported.")
        XCTAssertNotNil(store.mesh)
        XCTAssertTrue(store.canSave)
        XCTAssertFalse(store.canUndo)
        store.retryMaterials()
        try await requests(2, importer)
        let prepared = try XCTUnwrap(ImportedMaterialRenderLoader.loadIfPresent(data: bytes))
        await importer.finish(1, prepared)
        await store.materialGeneration?.value
        XCTAssertNil(store.materialIssue)
        XCTAssertNotNil(store.importedMaterials)
        let inputs = await importer.inputs
        XCTAssertEqual(inputs, [bytes, bytes])
    }

    private func settle(_ store: EditorStore) async {
        for _ in 0..<500 where store.isWorking { try? await Task.sleep(for: .milliseconds(5)) }
        await store.generation?.value
        await store.materialGeneration?.value
    }

    private func requests(_ count: Int, _ importer: SuspendedEditorImporter) async throws {
        for _ in 0..<500 {
            if await importer.inputs.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Imported material request was not enqueued")
    }
}

private actor SuspendedEditorImporter: ArchiveImportedMaterialLoading {
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
    func fail(_ index: Int, _ error: any Error) {
        pending[index]?.resume(throwing: error)
        pending[index] = nil
    }
}
