import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class MeshBakingServiceTests: XCTestCase {
    func testBackgroundServiceReturnsIndependentSendableOutput() async throws {
        let data = try fixture()
        let service = MeshBakingService()
        let options = MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8)
        let result = try await service.load(data: data, options: options)
        XCTAssertEqual(result.geometry.triangleCount, 80)
        XCTAssertEqual(result.textures.color.pixels.count, 256)
        let second = try await service.load(data: data, options: options)
        XCTAssertEqual(result.textures.color, second.textures.color)
    }

    func testPreCancelledTaskDoesNotLoadInvalidArchive() async throws {
        let service = MeshBakingService()
        let task = Task { try await service.load(data: Data()) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled request must not enter archive loading")
        } catch is CancellationError {
        }
    }

    func testTokenCancellationAndCloseAreIdempotentAndRaceSafe() async throws {
        var error = Dust3DError()
        let pointer = try XCTUnwrap(dust3d_cancellation_token_create(&error))
        let token = NativeBakeCancellation(pointer)
        token.cancel()
        XCTAssertEqual(dust3d_cancellation_token_is_cancelled(pointer), 1)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    if index.isMultiple(of: 2) { token.cancel() } else { token.close() }
                }
            }
        }
        token.cancel()
        token.close()
    }

    func testCancellationReachesNativeTokenDuringAnActiveRequest() async throws {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let proceed = DispatchSemaphore(value: 0)
        let service = MeshBakingService(operation: GatedBakeOperation(started: continuation, proceed: proceed))
        let data = try fixture()
        let task = Task {
            try await service.load(data: data, options: MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8))
        }
        var iterator = started.makeAsyncIterator()
        let entered: Void? = await iterator.next()
        XCTAssertNotNil(entered)
        task.cancel()
        proceed.signal()
        do {
            _ = try await task.value
            XCTFail("An active cancelled request must not publish a bake")
        } catch is CancellationError {
        }
    }

    private func fixture() throws -> Data {
        try Data(
            contentsOf: XCTUnwrap(
                Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures")))
    }
}

private enum BakeGateError: Error {
    case timedOut
    case nativeCancellationMissing
}

private struct GatedBakeOperation: MeshBakingOperation {
    let started: AsyncStream<Void>.Continuation
    let proceed: DispatchSemaphore

    func load(data: Data, images: [MeshBakeImage], options: MeshBakeOptions, cancellation: OpaquePointer) throws
        -> MeshWithBakedTextures
    {
        started.yield(())
        started.finish()
        guard proceed.wait(timeout: .now() + 5) == .success else { throw BakeGateError.timedOut }
        guard dust3d_cancellation_token_is_cancelled(cancellation) == 1 else {
            throw BakeGateError.nativeCancellationMissing
        }
        return try MeshLoader.loadBaked(data: data, images: images, options: options, cancellation: cancellation)
    }
}
