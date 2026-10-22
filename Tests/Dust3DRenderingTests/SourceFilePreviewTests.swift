import Dust3DDocument
import Metal
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class SourceFilePreviewTests: XCTestCase {
    func testSourceFrameClearsLegacyDetailNoticeButFallbackRestoresIt() async throws {
        let loaded = try await FilePreviewDocumentService().load(url: fixture())
        let original = try XCTUnwrap(loaded.mesh)
        let warning =
            "Untextured preview: image textures and procedural surface details are not yet displayed. "
            + "Imported geometry preview: GLB materials, textures and transparency are not yet applied."
        let mesh = IndexedMesh(
            vertices: original.vertices, indices: original.indices,
            nodeCount: original.nodeCount, partCount: original.partCount, warning: warning)
        let document = FilePreviewDocument(
            mesh: mesh, materials: loaded.materials, materialError: nil,
            materialSourceCapabilities: .known(hasLegacySurfaceDetails: true))
        XCTAssertNotNil(document.sourceBakedMesh)
        XCTAssertEqual(document.compatibilityWarning(), warning)
        XCTAssertNil(document.compatibilityWarning(materialsRendered: true))
        XCTAssertEqual(document.compatibilityWarning(materialsRendered: true, materialRenderingFailed: true), warning)
    }

    func testPreparesMixedFileReadOnlyAndClearsOnlyCurrentMaterialNotices() async throws {
        let url = fixture()
        let original = try Data(contentsOf: url)
        let document = try await FilePreviewDocumentService().load(url: url)
        let source = try XCTUnwrap(document.sourceBakedMesh)
        XCTAssertEqual(document.mesh?.triangleCount, 20)
        XCTAssertTrue(source.triangles.contains { $0.modelIndex == 0 && $0.packedUVs != nil })
        XCTAssertTrue(source.triangles.contains { $0.modelIndex == nil && $0.packedUVs != nil })
        XCTAssertNil(document.importedMaterials)
        XCTAssertNil(document.bakedMesh)
        XCTAssertNil(document.materialError)
        XCTAssertNotNil(document.compatibilityWarning())
        XCTAssertNil(document.compatibilityWarning(materialsRendered: true))
        XCTAssertEqual(
            document.compatibilityWarning(materialsRendered: true, materialRenderingFailed: true),
            document.mesh?.warning)
        XCTAssertEqual(try Data(contentsOf: url), original)
        let archive = try Dust3DDocument(data: original)
        XCTAssertEqual(archive.encoded(), original)
        XCTAssertEqual(archive.asset(named: "opaque.bin"), Data([19, 20, 21]))
    }

    func testForwardsExplicitPreviewSourceBudgetsAndExactArchiveBytes() async throws {
        let bytes = try Data(contentsOf: fixture())
        let source = try await ArchiveSourceTextureBakingService().load(
            data: bytes,
            options: SourceMeshBakeOptions(
                bake: MeshBakeOptions(colorSize: 512, normalSize: 256, materialSize: 256, atlasTextureSize: 256)))
        let baker = RecordedPreviewSourceBaker(result: .success(source))
        let document = try await FilePreviewDocumentService(sourceMaterialBaker: baker).load(url: fixture())
        XCTAssertNotNil(document.sourceBakedMesh)
        let records = await baker.records
        let record = try XCTUnwrap(records.first)
        let mib = 1024 * 1024
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.data, bytes)
        XCTAssertEqual(record.options.maximumNativePayloadBytes, 64 * mib)
        XCTAssertEqual(record.options.maximumCopiedPayloadBytes, 64 * mib)
        XCTAssertEqual(record.options.maximumInputImageBytes, 64 * mib)
        XCTAssertEqual(record.options.maximumSamplerPayloadBytes, 32 * mib)
        XCTAssertEqual(record.options.maximumAtlasPayloadBytes, 32 * mib)
        XCTAssertEqual(record.options.bake.maximumMetadataPayloadBytes, 16 * mib)
        XCTAssertEqual(record.options.bake.maximumBakePayloadBytes, 32 * mib)
        XCTAssertEqual(record.options.bake.atlasTextureSize, 256)
        XCTAssertEqual(record.options.bake.materialSize, 256)
        XCTAssertEqual(record.limits.textures.maximumEncodedImageBytes, 16 * mib)
        XCTAssertEqual(record.limits.textures.maximumEncodedTotalBytes, 32 * mib)
        XCTAssertEqual(record.limits.textures.maximumDecodedTotalBytes, 64 * mib)
        XCTAssertEqual(record.limits.materials.maximumNativePayloadBytes, 64 * mib)
        XCTAssertEqual(record.limits.materials.maximumCopiedPayloadBytes, 64 * mib)
        XCTAssertEqual(try Data(contentsOf: fixture()), bytes)
    }

    func testRetainsOrdinaryGeometryAndOriginalSourceFailureButPropagatesCancellation() async throws {
        let bytes = try Data(contentsOf: fixture())
        let failure = RecordedPreviewSourceBaker(result: .failure(SourceMeshBakeError.copyLimitExceeded))
        let document = try await FilePreviewDocumentService(sourceMaterialBaker: failure).load(url: fixture())
        XCTAssertEqual(document.mesh?.triangleCount, 20)
        XCTAssertNil(document.sourceBakedMesh)
        XCTAssertNil(document.materials)
        XCTAssertEqual(document.materialError as? SourceMeshBakeError, .copyLimitExceeded)
        let cancelled = RecordedPreviewSourceBaker(result: .failure(CancellationError()))
        do {
            _ = try await FilePreviewDocumentService(sourceMaterialBaker: cancelled).load(url: fixture())
            XCTFail("Cancellation cannot publish a partial preview")
        } catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf: fixture()), bytes)
    }

    func testCancellingInFlightPreparationDoesNotBlockTheNextPreviewRequest() async throws {
        let url = fixture()
        let original = try Data(contentsOf: url)
        let baker = SuspendedPreviewSourceBaker()
        let service = FilePreviewDocumentService(sourceMaterialBaker: baker)
        let request = Task { try await service.load(url: url) }
        await baker.waitUntilStarted()
        request.cancel()
        await baker.release()
        do {
            _ = try await request.value
            XCTFail("Cancelled preparation must not publish geometry or materials")
        } catch is CancellationError {}
        let next = try await service.load(url: url)
        XCTAssertEqual(next.mesh?.triangleCount, 20)
        XCTAssertEqual(next.materialError as? SourceMeshBakeError, .copyLimitExceeded)
        XCTAssertNil(next.materials)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testRendersSourceAlphaPolicyThroughProductionReadback() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device is available") }
        let cases: [(ImportedAlphaMode, Double, UInt8, UInt8)] = [
            (.opaque, .greatestFiniteMagnitude, 0, 255),
            (.mask, 0.5, 128, 255), (.mask, 0.6, 128, 0), (.mask, 1.5, 255, 0),
            (.mask, 0, 0, 255), (.mask, .leastNonzeroMagnitude, 0, 0),
            (.blend, .greatestFiniteMagnitude, 128, 128),
        ]
        for (mode, cutoff, alpha, expected) in cases {
            let baked = try BakedMetalFixture.quad(color: BakedMetalFixture.image([255, 0, 0, alpha]))
            let source = BakedMetalFixture.source(
                baked, policy: SourceBakedPolicy(alphaMode: mode, alphaCutoff: cutoff, isDoubleSided: true))
            let image = try await FilePreviewRenderer.render(
                sourceBakedMesh: source, maximumSize: CGSize(width: 13, height: 7), scale: 1)
            let center = (3 * 13 + 6) * 4
            XCTAssertEqual(image.width, 13)
            XCTAssertEqual(image.height, 7)
            XCTAssertEqual(image.pixels[center + 3], expected)
            XCTAssertLessThanOrEqual(image.pixels[center + 2], expected)
            XCTAssertEqual(try image.makeCGImage().width, 13)
        }
    }

    func testRepresentationDispatchHonorsGpuUploadQuotaBeforeAllocatingResources() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let baked = try BakedMetalFixture.quad()
        let builder = TexturedMetalResourcesBuilder()
        for input in [
            TexturedMaterialInput.legacy(baked), .source(BakedMetalFixture.source(baked, policy: nil)),
        ] {
            do {
                _ = try await builder.make(input: input, device: device, camera: OrbitCamera(), maximumPayloadBytes: 1)
                XCTFail("Representation dispatch must preserve the caller's upload quota")
            } catch { XCTAssertEqual(error as? TexturedRenderGeometryError, .payloadLimitExceeded) }
        }
    }

    func testRendersEveryRealDocumentRepresentationThroughSharedThumbnailRoute() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device is available") }
        for name in ["Capsule", "ImportedSurface", "MixedMaterials"] {
            let url = fixture(name)
            let before = try Data(contentsOf: url)
            let document = try await FilePreviewDocumentService().load(url: url)
            let rendered = try await FilePreviewRenderer.render(
                document: document, maximumSize: CGSize(width: 128, height: 128), scale: 1)
            XCTAssertNil(rendered.materialError)
            XCTAssertEqual(rendered.image.width, 128)
            XCTAssertEqual(rendered.image.height, 128)
            XCTAssertTrue(
                stride(from: 3, to: rendered.image.pixels.count, by: 4).contains { rendered.image.pixels[$0] > 0 })
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    func testMaterialRendererFailureStillProducesAnOrdinaryObjectImageWithItsOriginalCause() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device is available") }
        let baked = try BakedMetalFixture.quad()
        let source = BakedMetalFixture.source(
            baked, policy: SourceBakedPolicy(alphaMode: .mask, alphaCutoff: .nan, isDoubleSided: true))
        let mesh = IndexedMesh(
            vertices: baked.geometry.vertices, indices: baked.geometry.vertices.indices.map { UInt32($0) },
            nodeCount: 2, partCount: 1, warning: "")
        let document = FilePreviewDocument(mesh: mesh, materials: .sourceBaked(source), materialError: nil)
        let result = try await FilePreviewRenderer.render(
            document: document, maximumSize: CGSize(width: 64, height: 64), scale: 1)
        XCTAssertEqual(result.materialError as? TexturedRenderGeometryError, .invalidSourceMetadata)
        XCTAssertTrue(stride(from: 3, to: result.image.pixels.count, by: 4).contains { result.image.pixels[$0] > 0 })
    }

    func testPublicDocumentRendererValidatesRequestsBeforeStartingAnyRendering() async throws {
        let empty = FilePreviewDocument(mesh: nil, materials: nil, materialError: nil)
        do {
            _ = try await FilePreviewRenderer.render(document: empty, maximumSize: .zero, scale: 1)
            XCTFail("Invalid dimensions must fail before empty-document handling")
        } catch { XCTAssertEqual(error as? FilePreviewError, .invalidDimensions) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FilePreviewRenderer.render(
                document: empty, maximumSize: CGSize(width: 64, height: 64), scale: 1)
        }
        do {
            _ = try await task.value
            XCTFail("A pre-cancelled request cannot start rendering")
        } catch is CancellationError {}
    }

    private func fixture(_ name: String = "MixedMaterials") -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/\(name).ds3")
    }

}

private struct PreviewSourceRecord: Sendable {
    let data: Data
    let options: SourceMeshBakeOptions
    let limits: ArchiveSourceTextureLimits
}

private actor RecordedPreviewSourceBaker: ArchiveSourceTextureBaking {
    let result: Result<SourceBakedMesh, any Error>
    private(set) var records: [PreviewSourceRecord] = []
    init(result: Result<SourceBakedMesh, any Error>) { self.result = result }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    {
        records.append(PreviewSourceRecord(data: data, options: options, limits: limits))
        return try result.get()
    }
}

private actor SuspendedPreviewSourceBaker: ArchiveSourceTextureBaking {
    private var hasStarted = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        isReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    {
        hasStarted = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
        if !isReleased { await withCheckedContinuation { releaseWaiter = $0 } }
        try Task.checkCancellation()
        throw SourceMeshBakeError.copyLimitExceeded
    }
}
