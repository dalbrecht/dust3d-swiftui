import Dust3DDocument
import Dust3DEditorModel
import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

private enum SurfaceRepairFailure: LocalizedError {
    case original, material, timeout
    var errorDescription: String? {
        switch self {
        case .original: return "Original unsupported finish source"
        case .material: return "Injected material preparation cause"
        case .timeout: return "Repair preview did not start"
        }
    }
}

/// Every preview in this regression is copied Swift data. No unsupported archive reaches native code.
private actor SurfaceRepairPreview: EditorPreviewServing {
    private var pending: [Int: CheckedContinuation<EditorPreviewResult, Never>] = [:]
    private(set) var inputs: [Data] = []
    private var shouldFail = false
    func failNext() { shouldFail = true }
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        let index = inputs.count
        inputs.append(data)
        let details = try Dust3DDocument(data: data).components().first?.wrapping.surfaceDetails
        if details?.scalarValue(.wrinkles) == nil || shouldFail {
            shouldFail = false
            throw SurfaceRepairFailure.original
        }
        return await withCheckedContinuation { pending[index] = $0 }
    }
    func reset(scopeID: UUID) {}
    func finish(_ index: Int) {
        let vertices = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)].map {
            MeshVertex(position: $0, normal: .init(0, 0, 1), color: .init(repeating: 1))
        }
        let mesh = IndexedMesh(vertices: vertices, indices: [0, 1, 2], nodeCount: 1, partCount: 1, warning: "")
        pending.removeValue(forKey: index)?.resume(
            returning: EditorPreviewResult(
                sourced: SourcedMeshGenerationResult(
                    mesh: mesh, sourceHints: nil, statistics: MeshGenerationStatistics(native: Dust3DGenerationStats()))
            ))
    }
    func finishAll() { for index in Array(pending.keys) { finish(index) } }
}
private struct SurfaceRepairNoImported: ArchiveImportedMaterialLoading {
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}
private struct SurfaceRepairNoNativeBaker: ArchiveTextureBaking {
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    { throw SurfaceRepairFailure.material }
}

@MainActor final class ComponentSurfaceRepairTests: XCTestCase {
    private func document(unsupported: Bool) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='n' partId='p' x='.5' y='.5' z='.5' radius='.2'/></nodes><edges/><parts><part id='p'/></parts><components><component id='g' wrap='Skin' wrapWrinkles='\(unsupported ? "future" : "0")'><component id='c' linkDataType='partId' linkData='p'/></component></components></canvas>"
                    .utf8))
    }
    private func store(_ preview: SurfaceRepairPreview) -> EditorStore {
        EditorStore(
            preview: preview, materialBaker: SurfaceRepairNoNativeBaker(),
            importedMaterialLoader: SurfaceRepairNoImported())
    }
    private func wait(_ count: Int, preview: SurfaceRepairPreview) async throws {
        for _ in 0..<300 {
            if await preview.inputs.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw SurfaceRepairFailure.timeout
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw SurfaceRepairFailure.timeout
    }
    func testRepairAfterInitialGeometryFailureRegeneratesAndKeepsCauseUntilSuccessWithOneUndo() async throws {
        let original = try document(unsupported: true)
        let preview = SurfaceRepairPreview()
        let store = store(preview)
        defer {
            store.stop()
            Task { await preview.finishAll() }
        }
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertNil(store.mesh)
        XCTAssertEqual(store.previewState.errorMessage, SurfaceRepairFailure.original.localizedDescription)
        store.selectComponent("g")
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        store.componentSurfaceAction(.scalar(.wrinkles, 0), target: .init(snapshot: before))()
        try await wait(2, preview: preview)
        XCTAssertEqual(store.previewState.errorMessage, SurfaceRepairFailure.original.localizedDescription)
        XCTAssertEqual(store.snapshot?.previewIdentity.geometry, before.previewIdentity.geometry)
        await preview.finish(1)
        try await settle(store)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.previewState.errorMessage)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.snapshot?.canUndo == true)
    }
    func testOldCancelledRepairCompletionCannotReplaceNewDocumentPreview() async throws {
        let preview = SurfaceRepairPreview()
        let store = store(preview)
        defer {
            store.stop()
            Task { await preview.finishAll() }
        }
        await store.load(data: try document(unsupported: true).encoded())
        try await settle(store)
        store.selectComponent("g")
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        store.componentSurfaceAction(.scalar(.wrinkles, 0), target: .init(snapshot: before))()
        try await wait(2, preview: preview)
        let oldTask = try XCTUnwrap(store.generation)
        let oldIdentity = store.snapshot?.documentIdentity
        await store.load(data: try document(unsupported: false).encoded())
        try await wait(3, preview: preview)
        XCTAssertNotEqual(store.snapshot?.documentIdentity, oldIdentity)
        XCTAssertNil(store.previewState.errorMessage)
        await preview.finish(1)
        await oldTask.value
        XCTAssertNil(store.mesh)
        XCTAssertTrue(store.isGenerating)
        await preview.finish(2)
        try await settle(store)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.previewState.errorMessage)
    }
    func testFinishEditRetriesStaleRetainedGeometryAndKeepsItsFailureWhilePending() async throws {
        let source = try document(unsupported: false)
        let preview = SurfaceRepairPreview()
        let store = store(preview)
        defer {
            store.stop()
            Task { await preview.finishAll() }
        }
        await store.load(data: source.encoded())
        try await wait(1, preview: preview)
        await preview.finish(0)
        try await settle(store)
        store.selectComponent("g")
        try await settle(store)
        await preview.failNext()
        store.setComponentWrapFaces("g", faces: "128")
        try await settle(store)
        XCTAssertNotNil(store.mesh)
        XCTAssertTrue(store.previewState.isStale)
        let before = try XCTUnwrap(store.snapshot)
        store.componentSurfaceAction(.scalar(.wrinkles, 1), target: .init(snapshot: before))()
        try await wait(3, preview: preview)
        XCTAssertEqual(store.previewState.errorMessage, SurfaceRepairFailure.original.localizedDescription)
        XCTAssertTrue(store.previewState.isStale)
        XCTAssertEqual(store.snapshot?.previewIdentity.geometry, before.previewIdentity.geometry)
        await preview.finish(2)
        try await settle(store)
        XCTAssertFalse(store.previewState.isStale)
        XCTAssertNil(store.previewState.errorMessage)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), before.document.encoded())
        XCTAssertTrue(
            store.snapshot?.canUndo == true, "Only the repair entry was undone; the earlier geometry edit remains")
    }

}
