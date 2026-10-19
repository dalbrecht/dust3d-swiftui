import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class SourceMeshBakingServiceTests: XCTestCase {
    func testReturnsOwnedResultAcrossActorBoundary() async throws {
        let data = try Data(
            contentsOf: XCTUnwrap(
                Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures")))
        let result = try await SourceMeshBakingService().load(
            data: data,
            options: SourceMeshBakeOptions(bake: MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8)))
        XCTAssertEqual(result.geometry.triangleCount, 80)
        XCTAssertEqual(result.maximumSamplingLod, 0)
    }

    func testPreCancelledRequestDoesNotEnterNativeLoading() async throws {
        let service = SourceMeshBakingService()
        let task = Task { try await service.load(data: Data()) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled work must not load")
        } catch is CancellationError {}
    }

    func testCancellationReachesNativeTokenAndCannotPublishCompletedOutput() async throws {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let proceed = DispatchSemaphore(value: 0)
        let service = SourceMeshBakingService(operation: GatedSourceBake(started: continuation, proceed: proceed))
        let task = Task { try await service.load(data: Data()) }
        var iterator = started.makeAsyncIterator()
        let entered: Void? = await iterator.next()
        XCTAssertNotNil(entered)
        task.cancel()
        proceed.signal()
        do {
            _ = try await task.value
            XCTFail("Cancelled output must not be published")
        } catch is CancellationError {}
    }

    func testPreservesOriginalOperationFailure() async throws {
        let service = SourceMeshBakingService(operation: FailingSourceBake())
        do {
            _ = try await service.load(data: Data())
            XCTFail("Operation must throw")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, 2)
            XCTAssertEqual(error.message, "original source failure")
        }
    }
}

private enum SourceBakeGateError: Error { case timedOut, missingCancellation }

private struct GatedSourceBake: SourceMeshBakingOperation {
    let started: AsyncStream<Void>.Continuation
    let proceed: DispatchSemaphore

    func load(
        data: Data, modelImages: [SourceMeshBakeImage], images: [MeshBakeImage], options: SourceMeshBakeOptions,
        cancellation: OpaquePointer
    ) throws -> SourceBakedMesh {
        started.yield(())
        started.finish()
        guard proceed.wait(timeout: .now() + 5) == .success else { throw SourceBakeGateError.timedOut }
        guard dust3d_cancellation_token_is_cancelled(cancellation) == 1 else {
            throw SourceBakeGateError.missingCancellation
        }
        let image = MeshTextureImage(width: 1, height: 1, rowStride: 4, pixels: Data([0, 0, 0, 255]))
        return SourceBakedMesh(
            geometry: Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: ""), triangles: [],
            modelIDs: [], components: [],
            textures: MeshTextureMaps(color: image, normal: nil, metallic: nil, roughness: nil, emissive: nil),
            maximumSamplingLod: 0, nativePayloadBytes: 0, copiedPayloadBytes: 0)
    }
}

private struct FailingSourceBake: SourceMeshBakingOperation {
    func load(
        data: Data, modelImages: [SourceMeshBakeImage], images: [MeshBakeImage], options: SourceMeshBakeOptions,
        cancellation: OpaquePointer
    ) throws -> SourceBakedMesh {
        throw MeshLoadingError(status: 2, message: "original source failure")
    }
}
