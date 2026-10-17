import Dust3DDocument
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

@MainActor
final class EditorPreviewFallbackTests: XCTestCase {
    func testOnlyGenerationAndResourceFailuresTryOrdinaryPreview() async throws {
        let data = try archive()
        let ordinary = try await MeshGenerationSession().generateIndexed(data: data)
        for status: UInt32 in [1, 2, 3, 4] {
            let cause = MeshLoadingError(status: status, message: "Original source association cause")
            let backend = FallbackBackend(sourceError: cause, ordinary: ordinary)
            let service = EditorPreviewService(makeSession: { _ in backend })
            if status == 3 || status == 4 {
                let result = try await service.generate(data, scopeID: UUID())
                XCTAssertNotNil(result.mesh)
                XCTAssertNil(result.output?.sourceHints)
                XCTAssertEqual(result.sourceIssue?.status, status)
                XCTAssertEqual(result.sourceIssue?.message, cause.message)
            } else {
                do {
                    _ = try await service.generate(data, scopeID: UUID())
                    XCTFail("Invalid/unsupported input must not retry")
                } catch let error as MeshLoadingError { XCTAssertEqual(error.message, cause.message) }
            }
            let calls = await backend.ordinaryCalls
            XCTAssertEqual(calls, status == 3 || status == 4 ? 1 : 0)
        }
    }

    func testBothFailedAttemptsPreserveTheirCausesWithoutDuplicateText() async throws {
        let data = try archive()
        let ordinary = try await MeshGenerationSession().generateIndexed(data: data)
        let cause = MeshLoadingError(status: 3, message: "Original source cause")
        for primary in ["Original geometry cause", cause.message] {
            let backend = FallbackBackend(sourceError: cause, ordinary: ordinary, mode: .failure(primary))
            let service = EditorPreviewService(makeSession: { _ in backend })
            do {
                _ = try await service.generate(data, scopeID: UUID())
                XCTFail("Both attempts failed")
            } catch let error as EditorPreviewFallbackError {
                XCTAssertEqual(error.source.message, cause.message)
                XCTAssertTrue(error.localizedDescription.contains(primary))
                XCTAssertTrue(error.localizedDescription.contains(cause.message))
                if primary == cause.message { XCTAssertEqual(error.localizedDescription, primary) }
            }
        }
    }

    func testCancellationBeforeFallbackDoesNotStartAnotherBackendCall() async throws {
        try await cancellation(mode: .suspendedSource, expectedOrdinaryCalls: 0)
    }

    func testCancellationDuringFallbackDiscardsItsSuccessfulResult() async throws {
        try await cancellation(mode: .suspendedOrdinary, expectedOrdinaryCalls: 1)
    }

    private func cancellation(mode: FallbackBackend.Mode, expectedOrdinaryCalls: Int) async throws {
        let data = try archive()
        let ordinary = try await MeshGenerationSession().generateIndexed(data: data)
        let backend = FallbackBackend(
            sourceError: MeshLoadingError(status: 4, message: "Original source budget cause"), ordinary: ordinary,
            mode: mode)
        let service = EditorPreviewService(makeSession: { _ in backend })
        let operation = Task { try await service.generate(data, scopeID: UUID()) }
        defer {
            operation.cancel()
            Task { await backend.release() }
        }
        for _ in 0..<300 {
            if await backend.isSuspended { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = await backend.isSuspended
        XCTAssertTrue(started)
        operation.cancel()
        await backend.release()
        do {
            _ = try await operation.value
            XCTFail("Cancellation cannot publish a fallback result")
        } catch is CancellationError {}
        let calls = await backend.ordinaryCalls
        XCTAssertEqual(calls, expectedOrdinaryCalls)
    }

    private func archive() throws -> Data {
        try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true).encoded()
    }
}

private actor FallbackBackend: EditorMeshGenerating {
    enum Mode: Sendable {
        case success
        case failure(String)
        case suspendedSource
        case suspendedOrdinary
    }
    private let sourceError: MeshLoadingError
    private let ordinary: MeshGenerationResult
    private let mode: Mode
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var ordinaryCalls = 0
    var isSuspended: Bool { continuation != nil }

    init(sourceError: MeshLoadingError, ordinary: MeshGenerationResult, mode: Mode = .success) {
        self.sourceError = sourceError
        self.ordinary = ordinary
        self.mode = mode
    }
    func generateSourcedIndexed(data: Data, maximumPayloadBytes: Int, maximumSourcePayloadBytes: Int) async throws
        -> SourcedMeshGenerationResult
    {
        if case .suspendedSource = mode { await withCheckedContinuation { continuation = $0 } }
        throw sourceError
    }
    func generateIndexed(data: Data, maximumPayloadBytes: Int) async throws -> MeshGenerationResult {
        ordinaryCalls += 1
        if case .suspendedOrdinary = mode { await withCheckedContinuation { continuation = $0 } }
        if case .failure(let message) = mode { throw GeometryFailure(message: message) }
        return ordinary
    }
    func reset() async throws {}
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private struct GeometryFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
