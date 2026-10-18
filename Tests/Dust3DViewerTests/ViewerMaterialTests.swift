import Foundation
import XCTest

@testable import Dust3DKit
@testable import Dust3DViewer

@MainActor
final class ViewerMaterialTests: XCTestCase {
    func testShouldKeepGeometryOnMaterialFailureAndRetryTheExactSnapshot() async throws {
        let snapshot = try snapshot()
        let baker = SuspendedViewerBaker()
        let store = ViewerStore(service: SnapshotLoader(snapshot: snapshot), materialBaker: baker)
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/model.ds3"))
        await store.loadTask?.value
        try await waitForRequests(1, baker)
        XCTAssertNotNil(store.mesh)
        XCTAssertFalse(store.isLoading)
        await baker.fail(0)
        await store.materialTask?.value
        XCTAssertNil(store.bakedMesh)
        XCTAssertEqual(store.materialIssue, "Original retained image cause")
        XCTAssertNil(store.errorMessage)
        store.retryMaterials()
        try await waitForRequests(2, baker)
        let inputs = await baker.inputs
        XCTAssertEqual(inputs, [snapshot.data, snapshot.data])
        await baker.fail(1)
        await store.materialTask?.value
        XCTAssertNotNil(store.mesh)
        XCTAssertFalse(store.isBakingMaterials)
    }

    func testShouldRejectOldMaterialResultsAfterReplacementAndStop() async throws {
        let snapshot = try snapshot()
        let baked = try await MeshBakingService().load(
            data: snapshot.data,
            options: MeshBakeOptions(colorSize: 32, normalSize: 16, materialSize: 8, atlasTextureSize: 32))
        let baker = SuspendedViewerBaker()
        let store = ViewerStore(service: SnapshotLoader(snapshot: snapshot), materialBaker: baker)
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/first.ds3"))
        await store.loadTask?.value
        try await waitForRequests(1, baker)
        let obsolete = try XCTUnwrap(store.materialTask)
        store.open(URL(fileURLWithPath: "/test/second.ds3"))
        await store.loadTask?.value
        try await waitForRequests(2, baker)
        await baker.finish(1, baked)
        await store.materialTask?.value
        let revision = store.materialRevision
        XCTAssertNotNil(store.bakedMesh)
        await baker.finish(0, baked)
        await obsolete.value
        XCTAssertEqual(store.materialRevision, revision)
        XCTAssertEqual(store.documentName, "second.ds3")
        store.materialFailed("Original GPU cause")
        XCTAssertNil(store.bakedMesh)
        XCTAssertNotNil(store.mesh)
        store.retryMaterials()
        try await waitForRequests(3, baker)
        let stopped = try XCTUnwrap(store.materialTask)
        store.stop()
        await baker.finish(2, baked)
        await stopped.value
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.bakedMesh)
        XCTAssertFalse(store.isBakingMaterials)
        XCTAssertFalse(store.isLoading)
    }

    func testShouldFinishProgressWhenTheCurrentServiceCancels() async throws {
        let snapshot = try snapshot()
        let baker = SuspendedViewerBaker()
        let store = ViewerStore(service: SnapshotLoader(snapshot: snapshot), materialBaker: baker)
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/model.ds3"))
        await store.loadTask?.value
        try await waitForRequests(1, baker)
        await baker.cancel(0)
        await store.materialTask?.value
        XCTAssertFalse(store.isBakingMaterials)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.bakedMesh)
        XCTAssertNotNil(store.materialIssue)
    }

    func testShouldPreserveFileErrorsAndRejectLateFileLoadsAfterStop() async throws {
        let snapshot = try snapshot()
        let loader = SuspendedSnapshotLoader()
        let store = ViewerStore(service: loader)
        defer { store.stop() }
        store.open(URL(fileURLWithPath: "/test/missing.ds3"))
        try await waitForFileRequests(1, loader)
        await loader.fail(0)
        await store.loadTask?.value
        XCTAssertEqual(store.errorMessage, "Original file access cause")
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.mesh)
        store.open(URL(fileURLWithPath: "/test/stopped.ds3"))
        try await waitForFileRequests(2, loader)
        let stopped = try XCTUnwrap(store.loadTask)
        store.stop()
        await loader.finish(1, snapshot)
        await stopped.value
        XCTAssertNil(store.mesh)
        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.isBakingMaterials)
    }

    private func waitForFileRequests(_ expected: Int, _ loader: SuspendedSnapshotLoader) async throws {
        for _ in 0..<300 {
            if await loader.count >= expected { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("File request was not enqueued")
    }

    private func snapshot() throws -> MeshFileSnapshot {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/Capsule.ds3")
        let data = try Data(contentsOf: fixture)
        return MeshFileSnapshot(data: data, mesh: try MeshLoader.loadIndexed(data: data))
    }

    private func waitForRequests(_ expected: Int, _ baker: SuspendedViewerBaker) async throws {
        for _ in 0..<300 {
            if await baker.inputs.count >= expected { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Material request was not enqueued")
    }
}

private actor SnapshotLoader: MeshFileSnapshotLoading {
    let snapshot: MeshFileSnapshot
    init(snapshot: MeshFileSnapshot) { self.snapshot = snapshot }
    func loadIndexedSnapshot(url: URL) async throws -> MeshFileSnapshot { snapshot }
}

private actor SuspendedViewerBaker: ArchiveTextureBaking {
    private(set) var inputs: [Data] = []
    private var pending: [CheckedContinuation<MeshWithBakedTextures, any Error>?] = []
    private enum Failure: LocalizedError {
        case image
        var errorDescription: String? { "Original retained image cause" }
    }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        inputs.append(data)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ index: Int, _ mesh: MeshWithBakedTextures) {
        pending[index]?.resume(returning: mesh)
        pending[index] = nil
    }
    func cancel(_ index: Int) {
        pending[index]?.resume(throwing: CancellationError())
        pending[index] = nil
    }
    func fail(_ index: Int) {
        pending[index]?.resume(throwing: Failure.image)
        pending[index] = nil
    }
}

private actor SuspendedSnapshotLoader: MeshFileSnapshotLoading {
    private var pending: [CheckedContinuation<MeshFileSnapshot, any Error>?] = []
    var count: Int { pending.count }
    private enum Failure: LocalizedError {
        case file
        var errorDescription: String? { "Original file access cause" }
    }
    func loadIndexedSnapshot(url: URL) async throws -> MeshFileSnapshot {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ index: Int, _ snapshot: MeshFileSnapshot) {
        pending[index]?.resume(returning: snapshot)
        pending[index] = nil
    }
    func fail(_ index: Int) {
        pending[index]?.resume(throwing: Failure.file)
        pending[index] = nil
    }
}
