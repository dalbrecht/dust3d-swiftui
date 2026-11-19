import Foundation
import XCTest

@testable import Dust3DKit
@testable import Dust3DViewer

@MainActor
final class ViewerMaterialTests: XCTestCase {
    func testRetryFailedOpenKeepsAcceptedMeshAndUsesOnlyTheCapturedFailure() async throws {
        let snapshot = try snapshot()
        let loader = SuspendedSnapshotLoader()
        let store = ViewerStore(service: loader)
        let accepted = URL(fileURLWithPath: "/test/accepted.ds3")
        let failed = URL(fileURLWithPath: "/test/failed.ds3")
        defer { store.stop() }

        store.open(accepted)
        try await waitForFileRequests(1, loader)
        await loader.finish(0, snapshot)
        await store.loadTask?.value
        let acceptedRevision = store.meshRevision

        store.open(failed)
        try await waitForFileRequests(2, loader)
        await loader.fail(1)
        await store.loadTask?.value
        let failure = try XCTUnwrap(store.openFailure)
        XCTAssertEqual(store.documentName, accepted.lastPathComponent)
        XCTAssertEqual(store.meshRevision, acceptedRevision)

        store.retryOpen(failure)
        try await waitForFileRequests(3, loader)
        let requests = await loader.requests
        XCTAssertEqual(requests, [accepted, failed, failed])
        XCTAssertNil(store.openFailure)
        XCTAssertEqual(store.meshRevision, acceptedRevision)
        await loader.finish(2, snapshot)
        await store.loadTask?.value

        store.retryOpen(failure)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.documentName, failed.lastPathComponent)
        XCTAssertEqual(store.meshRevision, acceptedRevision + 1)
    }

    func testViewerCameraAndWireframeCommandsStayWithTheirWindowAndAcceptedMesh() async throws {
        let snapshot = try snapshot()
        let first = ViewerStore(service: SnapshotLoader(snapshot: snapshot))
        let second = ViewerStore(service: SnapshotLoader(snapshot: snapshot))
        defer {
            first.stop()
            second.stop()
        }

        first.setWireframe(true)
        first.fitModel()
        first.moveCamera(.zoomIn)
        XCTAssertFalse(first.isWireframe)
        XCTAssertEqual(first.cameraState.revision, 0)

        first.open(URL(fileURLWithPath: "/test/first.ds3"))
        await first.loadTask?.value
        second.open(URL(fileURLWithPath: "/test/second.ds3"))
        await second.loadTask?.value
        let camera = first.cameraState
        first.setWireframe(true)
        first.moveCamera(.zoomIn)
        first.moveCamera(.zoomIn)
        XCTAssertEqual(camera.revision, 2)
        XCTAssertEqual(second.cameraState.revision, 0)
        XCTAssertTrue(first.isWireframe)
        XCTAssertFalse(second.isWireframe)
        first.fitModel()
        XCTAssertEqual(camera.revision, 3)
        XCTAssertEqual(second.cameraState.revision, 0)

        first.moveCamera(.zoomOut)
        first.open(URL(fileURLWithPath: "/test/replacement.ds3"))
        await first.loadTask?.value
        XCTAssertFalse(first.cameraState === camera)
        XCTAssertEqual(first.cameraState.revision, 0)
        XCTAssertEqual(camera.revision, 4)
        XCTAssertTrue(first.isWireframe)
    }

    func testWireframeBindingBelongsToTheWindowAndRequiresAnAcceptedMesh() async throws {
        let snapshot = try snapshot()
        let first = ViewerStore(service: SnapshotLoader(snapshot: snapshot))
        let second = ViewerStore(service: SnapshotLoader(snapshot: snapshot))
        defer { second.stop() }

        let wireframe = first.wireframeBinding
        wireframe.wrappedValue = true
        XCTAssertFalse(first.isWireframe)

        first.open(URL(fileURLWithPath: "/test/first.ds3"))
        second.open(URL(fileURLWithPath: "/test/second.ds3"))
        await first.loadTask?.value
        await second.loadTask?.value

        wireframe.wrappedValue = true
        XCTAssertTrue(first.isWireframe)
        XCTAssertFalse(second.wireframeBinding.wrappedValue)
        wireframe.wrappedValue = false
        XCTAssertFalse(first.isWireframe)

        wireframe.wrappedValue = true
        first.stop()
        XCTAssertFalse(wireframe.wrappedValue)
    }

    func testAutomaticRotationBelongsToTheWindowAndRequiresAnAcceptedMesh() async throws {
        let snapshot = try snapshot()
        let first = ViewerStore(service: SnapshotLoader(snapshot: snapshot))
        let second = ViewerStore(service: SnapshotLoader(snapshot: snapshot))
        defer { second.stop() }

        first.setAutomaticallyRotates(true)
        XCTAssertFalse(first.automaticallyRotates)

        first.open(URL(fileURLWithPath: "/test/first.ds3"))
        second.open(URL(fileURLWithPath: "/test/second.ds3"))
        await first.loadTask?.value
        await second.loadTask?.value
        XCTAssertFalse(first.automaticallyRotates)

        first.setAutomaticallyRotates(true)
        XCTAssertTrue(first.automaticallyRotates)
        XCTAssertFalse(second.automaticallyRotates)
        first.setAutomaticallyRotates(false)
        XCTAssertFalse(first.automaticallyRotates)

        first.setAutomaticallyRotates(true)
        first.stop()
        XCTAssertFalse(first.automaticallyRotates)
    }

    func testFinderDropOpensTheLastLocalDust3DFileInTheReceivingViewer() async throws {
        let snapshot = try snapshot()
        let loader = SuspendedSnapshotLoader()
        let store = ViewerStore(service: loader)
        let other = ViewerStore(service: loader)
        defer {
            store.stop()
            other.stop()
        }
        let remote = try XCTUnwrap(URL(string: "https://example.com/remote.ds3"))
        let networkFile = try XCTUnwrap(URL(string: "file://example.com/remote.ds3"))
        let invalid = [
            remote, networkFile, URL(fileURLWithPath: "/test/notes.txt"),
            URL(fileURLWithPath: "/test/folder.ds3", isDirectory: true),
        ]
        XCTAssertFalse(store.openDroppedDocuments(invalid))
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.loadTask)

        let first = URL(fileURLWithPath: "/test/first.ds3")
        let chosen = URL(fileURLWithPath: "/test/chosen.DS3")
        XCTAssertTrue(store.openDroppedDocuments([first, chosen] + invalid))
        try await waitForFileRequests(1, loader)
        let initial = await loader.requests
        XCTAssertEqual(initial, [chosen])
        XCTAssertFalse(other.isLoading)
        XCTAssertNil(other.mesh)
        await loader.finish(0, snapshot)
        await store.loadTask?.value
        XCTAssertEqual(store.documentName, chosen.lastPathComponent)
        let acceptedRevision = store.meshRevision

        XCTAssertTrue(store.openDroppedDocuments([first]))
        try await waitForFileRequests(2, loader)
        await loader.fail(1)
        await store.loadTask?.value
        XCTAssertEqual(store.documentName, chosen.lastPathComponent)
        XCTAssertEqual(store.meshRevision, acceptedRevision)
        XCTAssertEqual(store.errorMessage, "Original file access cause")
    }

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
        await baker.fail(
            0, error: ArchiveTextureBakingError.imageDecoding(assetName: "images/broken.png", cause: .invalidPNG))
        await store.materialTask?.value
        XCTAssertNil(store.bakedMesh)
        XCTAssertTrue(store.materialIssue?.contains("images/broken.png") == true)
        XCTAssertTrue(store.materialIssue?.contains("PNG") == true)
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
        let original = try snapshot()
        let snapshot = MeshFileSnapshot(
            data: original.data, mesh: original.mesh,
            materialSourceCapabilities: .unavailable(cause: ViewerSourceFailure.original))
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
        XCTAssertNil(store.materialSourceIssue)
    }

    func testMaterialNoticeTracksCurrentRenderingAndKeepsSourceFailureCause() async throws {
        let original = try snapshot()
        let warning = "Untextured preview: image textures and procedural surface details are not yet displayed."
        let mesh = IndexedMesh(
            vertices: original.mesh.vertices, indices: original.mesh.indices,
            nodeCount: original.mesh.nodeCount, partCount: original.mesh.partCount, warning: warning)
        let baked = try await MeshBakingService().load(
            data: original.data,
            options: MeshBakeOptions(colorSize: 32, normalSize: 16, materialSize: 8, atlasTextureSize: 32))
        for capabilities in [
            MaterialSourceCapabilities.known(hasLegacySurfaceDetails: false),
            .known(hasLegacySurfaceDetails: true), .unavailable(cause: ViewerSourceFailure.original),
        ] {
            let snapshot = MeshFileSnapshot(data: original.data, mesh: mesh, materialSourceCapabilities: capabilities)
            let baker = SuspendedViewerBaker()
            let store = ViewerStore(service: SnapshotLoader(snapshot: snapshot), materialBaker: baker)
            defer { store.stop() }
            store.open(URL(fileURLWithPath: "/test/image.ds3"))
            await store.loadTask?.value
            try await waitForRequests(1, baker)
            XCTAssertEqual(store.previewCompatibilityWarning, warning)
            await baker.finish(0, baked)
            await store.materialTask?.value
            XCTAssertEqual(store.previewCompatibilityWarning, warning, "CPU baking must not imply GPU readiness")
            store.materialsRendered(revision: store.meshRevision + store.materialRevision - 1)
            XCTAssertEqual(store.previewCompatibilityWarning, warning)
            store.materialsRendered(revision: store.meshRevision + store.materialRevision)
            XCTAssertNil(
                store.previewCompatibilityWarning,
                "A matching procedural bake receipt establishes surface pixels without trusting source-capability guesses"
            )
            if case .unavailable = capabilities {
                XCTAssertEqual(store.materialSourceIssue, "Original source interpretation cause")
            }
            store.materialFailed("Original GPU failure")
            XCTAssertEqual(store.previewCompatibilityWarning, warning)
            XCTAssertEqual(store.materialIssue, "Original GPU failure")
            store.stop()
            XCTAssertNil(store.previewCompatibilityWarning)
            XCTAssertNil(store.materialSourceIssue)
        }
    }

    func testRetainsAcceptedMaterialsAcrossPendingAndFailedReplacementThenSwapsOnSuccess() async throws {
        let first = try copiedFrame(1)
        let second = try copiedFrame(2)
        let loader = SuspendedSnapshotLoader()
        let baker = SuspendedViewerBaker()
        let store = ViewerStore(
            service: loader, materialBaker: baker, importedMaterialLoader: NoImportedViewerMaterials())
        defer { store.stop() }

        store.open(URL(fileURLWithPath: "/test/first.ds3"))
        try await waitForFileRequests(1, loader)
        await loader.finish(0, first.snapshot)
        await store.loadTask?.value
        try await waitForRequests(1, baker)
        await baker.finish(0, first.baked)
        await store.materialTask?.value
        let meshRevision = store.meshRevision
        let materialRevision = store.materialRevision
        let renderRevision = meshRevision + materialRevision
        store.materialsRendered(revision: renderRevision)

        store.open(URL(fileURLWithPath: "/test/broken.ds3"))
        try await waitForFileRequests(2, loader)
        XCTAssertTrue(store.isLoading)
        XCTAssertEqual(store.documentName, "first.ds3")
        XCTAssertEqual(store.bakedMesh?.textures.color, first.baked.textures.color)
        XCTAssertEqual(store.meshRevision, meshRevision)
        XCTAssertEqual(store.materialRevision, materialRevision)
        XCTAssertFalse(store.isUpdatingMaterials)
        await loader.fail(1)
        await store.loadTask?.value
        XCTAssertEqual(store.errorMessage, "Original file access cause")
        XCTAssertEqual(store.documentName, "first.ds3")
        XCTAssertEqual(store.bakedMesh?.textures.color, first.baked.textures.color)
        XCTAssertFalse(store.isUpdatingMaterials)

        store.open(URL(fileURLWithPath: "/test/second.ds3"))
        try await waitForFileRequests(3, loader)
        XCTAssertEqual(store.bakedMesh?.textures.color, first.baked.textures.color)
        await loader.finish(2, second.snapshot)
        await store.loadTask?.value
        try await waitForRequests(2, baker)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.documentName, "second.ds3")
        XCTAssertEqual(store.meshRevision, meshRevision + 1)
        XCTAssertNil(store.bakedMesh)
        let inputs = await baker.inputs
        XCTAssertEqual(inputs, [first.snapshot.data, second.snapshot.data])
        await baker.finish(1, second.baked)
        await store.materialTask?.value
        store.materialsFailed("Old viewport failure", revision: renderRevision)
        XCTAssertNil(store.materialIssue)
        XCTAssertEqual(store.bakedMesh?.textures.color, second.baked.textures.color)
        XCTAssertTrue(store.isUpdatingMaterials)
        store.materialsRendered(revision: store.meshRevision + store.materialRevision)
        XCTAssertFalse(store.isUpdatingMaterials)
    }

    func testModelColorPresentationIsWindowLocalAndDoesNotRebake() async throws {
        let frame = try copiedFrame(1)
        let loader = SuspendedSnapshotLoader()
        let baker = SuspendedViewerBaker()
        let store = ViewerStore(
            service: loader, materialBaker: baker, importedMaterialLoader: NoImportedViewerMaterials())
        let otherWindow = ViewerStore(
            service: loader, materialBaker: baker, importedMaterialLoader: NoImportedViewerMaterials())
        defer {
            store.stop()
            otherWindow.stop()
        }

        store.open(URL(fileURLWithPath: "/test/first.ds3"))
        try await waitForFileRequests(1, loader)
        await loader.finish(0, frame.snapshot)
        await store.loadTask?.value
        try await waitForRequests(1, baker)

        store.open(URL(fileURLWithPath: "/test/broken.ds3"))
        try await waitForFileRequests(2, loader)
        await baker.finish(0, frame.baked)
        await store.materialTask?.value
        XCTAssertTrue(store.isLoading)
        XCTAssertEqual(store.bakedMesh?.textures.color, frame.baked.textures.color)
        let meshRevision = store.meshRevision
        let materialRevision = store.materialRevision
        store.materialsRendered(revision: meshRevision + materialRevision)

        XCTAssertTrue(store.showsModelColors)
        store.setModelColors(false)
        XCTAssertFalse(store.showsModelColors)
        XCTAssertTrue(otherWindow.showsModelColors)
        XCTAssertEqual(store.meshRevision, meshRevision)
        XCTAssertEqual(store.materialRevision, materialRevision)
        XCTAssertEqual(store.bakedMesh?.textures.color, frame.baked.textures.color)
        XCTAssertFalse(store.isUpdatingMaterials)
        let inputs = await baker.inputs
        XCTAssertEqual(inputs, [frame.snapshot.data])
        await loader.fail(1)
        await store.loadTask?.value
        XCTAssertFalse(store.showsModelColors)
        XCTAssertEqual(store.errorMessage, "Original file access cause")
    }

    private func copiedFrame(_ byte: UInt8) throws -> (snapshot: MeshFileSnapshot, baked: MeshWithBakedTextures) {
        let vertices = [SIMD3<Float>(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)].map {
            MeshVertex(position: $0, normal: SIMD3(0, 0, 1), color: SIMD4(1, 0, 0, 1))
        }
        let geometry = IndexedMesh(vertices: vertices, indices: [0, 1, 2], nodeCount: 3, partCount: 1, warning: "")
        let snapshot = MeshFileSnapshot(data: Data([byte]), mesh: geometry)
        let triangle = RawMeshUvTriangle(
            corners: MeshUvCorners(first: .zero, second: .zero, third: .zero), known: 0,
            componentKind: 0, componentIndex: -1)
        let metadata = try MeshUvMetadata(
            componentIDs: [], triangles: [triangle], charts: [], gradients: [],
            expandedVertexCount: vertices.count, packedTextureSize: 0)
        let image = MeshTextureImage(width: 1, height: 1, rowStride: 4, pixels: Data([byte, 0, 0, 255]))
        let baked = MeshWithBakedTextures(
            geometry: Mesh(vertices: vertices, nodeCount: 3, partCount: 1, warning: ""),
            metadata: metadata, tangents: [],
            textures: MeshTextureMaps(color: image, normal: nil, metallic: nil, roughness: nil, emissive: nil))
        return (snapshot, baked)
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
    func fail(_ index: Int, error: any Error = Failure.image) {
        pending[index]?.resume(throwing: error)
        pending[index] = nil
    }
}

private actor SuspendedSnapshotLoader: MeshFileSnapshotLoading {
    private(set) var requests: [URL] = []
    private var pending: [CheckedContinuation<MeshFileSnapshot, any Error>?] = []
    var count: Int { pending.count }
    private enum Failure: LocalizedError {
        case file
        var errorDescription: String? { "Original file access cause" }
    }
    func loadIndexedSnapshot(url: URL) async throws -> MeshFileSnapshot {
        requests.append(url)
        return try await withCheckedThrowingContinuation { pending.append($0) }
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

private enum ViewerSourceFailure: LocalizedError {
    case original
    var errorDescription: String? { "Original source interpretation cause" }
}

private struct NoImportedViewerMaterials: ArchiveImportedMaterialLoading {
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}
