import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit
@testable import Dust3DViewer

@MainActor
final class ViewerSourceBakedMaterialTests: XCTestCase {
    func testPreparesBothMixedSurfaceKindsAndWaitsForMatchingGpuFrame() async throws {
        let snapshot = try snapshot(
            warning:
                "Untextured preview: image textures and procedural surface details are not yet displayed. "
                + "Imported geometry preview: GLB materials, textures and transparency are not yet applied.")
        let original = snapshot.data
        let store = ViewerStore(service: SourceViewerSnapshotLoader(snapshot: snapshot))
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/mixed.ds3"))
        await store.loadTask?.value
        await store.materialTask?.value
        let source = try XCTUnwrap(store.sourceBakedMesh)
        XCTAssertNil(store.bakedMesh)
        XCTAssertNil(store.importedMaterials)
        XCTAssertTrue(source.triangles.contains { $0.modelIndex == 0 && $0.packedUVs != nil })
        XCTAssertTrue(source.triangles.contains { $0.modelIndex == nil && $0.packedUVs != nil })
        XCTAssertEqual(source.maximumSamplingLod, 0)
        XCTAssertNil(store.materialIssue)
        XCTAssertTrue(store.isUpdatingMaterials)
        XCTAssertNotNil(store.previewCompatibilityWarning)
        let revision = store.meshRevision + store.materialRevision
        store.materialsRendered(revision: revision - 1)
        XCTAssertTrue(store.isUpdatingMaterials)
        store.materialsRendered(revision: revision)
        XCTAssertNil(store.previewCompatibilityWarning)
        XCTAssertFalse(store.isUpdatingMaterials)
        store.materialsFailed("stale GPU failure", revision: revision - 1)
        XCTAssertNotNil(store.sourceBakedMesh)
        store.materialsFailed("original mixed GPU failure", revision: revision)
        XCTAssertNil(store.sourceBakedMesh)
        XCTAssertNotNil(store.mesh)
        XCTAssertEqual(store.materialIssue, "original mixed GPU failure")
        XCTAssertEqual(snapshot.data, original)
        let document = try Dust3DDocument(data: original)
        XCTAssertEqual(document.encoded(), original)
        XCTAssertEqual(document.asset(named: "opaque.bin"), Data([19, 20, 21]))
        let imported = try Dust3DDocument(data: fixture("ImportedSurface"))
        let model = "models/{00000300-0000-4000-8000-000000000300}.glb"
        XCTAssertEqual(document.asset(named: model), imported.asset(named: model))
    }

    func testRejectsLateSourceBakesAfterReplacementAndStop() async throws {
        let snapshot = try snapshot()
        let output = try await ArchiveSourceTextureBakingService().load(
            data: snapshot.data,
            options: SourceMeshBakeOptions(
                bake: MeshBakeOptions(colorSize: 512, normalSize: 256, materialSize: 256, atlasTextureSize: 256)))
        let baker = SuspendedViewerSourceBaker()
        let store = ViewerStore(service: SourceViewerSnapshotLoader(snapshot: snapshot), sourceMaterialBaker: baker)
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/first.ds3"))
        await store.loadTask?.value
        try await waitForRequests(1, baker)
        let old = try XCTUnwrap(store.materialTask)
        store.open(URL(fileURLWithPath: "/test/second.ds3"))
        await store.loadTask?.value
        try await waitForRequests(2, baker)
        await baker.finish(1, output)
        await store.materialTask?.value
        let revision = store.materialRevision
        await baker.finish(0, output)
        await old.value
        XCTAssertEqual(store.materialRevision, revision)
        XCTAssertEqual(store.documentName, "second.ds3")
        XCTAssertNotNil(store.sourceBakedMesh)
        store.retryMaterials()
        try await waitForRequests(3, baker)
        let stopped = try XCTUnwrap(store.materialTask)
        store.stop()
        await baker.finish(2, output)
        await stopped.value
        XCTAssertNil(store.sourceBakedMesh)
        XCTAssertNil(store.mesh)
        XCTAssertFalse(store.isUpdatingMaterials)
    }

    func testPreservesSourceBakeFailureAndRetriesExactArchiveSnapshot() async throws {
        let snapshot = try snapshot()
        let baker = SuspendedViewerSourceBaker()
        let store = ViewerStore(service: SourceViewerSnapshotLoader(snapshot: snapshot), sourceMaterialBaker: baker)
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/mixed.ds3"))
        await store.loadTask?.value
        try await waitForRequests(1, baker)
        await baker.fail(0, MeshLoadingError(status: 4, message: "original mixed bake failure"))
        await store.materialTask?.value
        XCTAssertTrue(store.materialIssue?.contains("original mixed bake failure") == true)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.sourceBakedMesh)
        store.retryMaterials()
        try await waitForRequests(2, baker)
        let inputs = await baker.inputs
        XCTAssertEqual(inputs, [snapshot.data, snapshot.data])
        await baker.fail(1, CancellationError())
        await store.materialTask?.value
        XCTAssertFalse(store.isBakingMaterials)
        XCTAssertNotNil(store.mesh)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/\(name).ds3")
        return try Data(contentsOf: url)
    }

    private func snapshot(warning: String? = nil) throws -> MeshFileSnapshot {
        let data = try fixture("MixedMaterials")
        let original = try MeshLoader.loadIndexed(data: data)
        let mesh = IndexedMesh(
            vertices: original.vertices, indices: original.indices,
            nodeCount: original.nodeCount, partCount: original.partCount, warning: warning ?? original.warning)
        return MeshFileSnapshot(
            data: data, mesh: mesh,
            materialSourceCapabilities: .known(hasLegacySurfaceDetails: true))
    }

    private func waitForRequests(_ count: Int, _ baker: SuspendedViewerSourceBaker) async throws {
        for _ in 0..<300 {
            if await baker.inputs.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Source bake was not enqueued")
    }
}

private actor SourceViewerSnapshotLoader: MeshFileSnapshotLoading {
    let snapshot: MeshFileSnapshot
    init(snapshot: MeshFileSnapshot) { self.snapshot = snapshot }
    func loadIndexedSnapshot(url: URL) async throws -> MeshFileSnapshot { snapshot }
}

private actor SuspendedViewerSourceBaker: ArchiveSourceTextureBaking {
    private(set) var inputs: [Data] = []
    private var pending: [CheckedContinuation<SourceBakedMesh, any Error>?] = []
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    {
        inputs.append(data)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ index: Int, _ output: SourceBakedMesh) {
        pending[index]?.resume(returning: output)
        pending[index] = nil
    }
    func fail(_ index: Int, _ error: any Error) {
        pending[index]?.resume(throwing: error)
        pending[index] = nil
    }
}
