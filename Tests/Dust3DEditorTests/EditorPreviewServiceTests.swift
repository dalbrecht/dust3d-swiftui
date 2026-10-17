import Dust3DDocument
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorPreviewServiceTests: XCTestCase {
    func testReusesOnlyWithinTheCurrentDocumentScope() async throws {
        let service = EditorPreviewService()
        let data = try archive()
        let firstScope = UUID()
        let secondScope = UUID()
        let cold = try await service.generate(data, scopeID: firstScope)
        let reused = try await service.generate(data, scopeID: firstScope)
        XCTAssertNotNil(cold.mesh)
        XCTAssertEqual(cold.statistics.reusedComponentCount, 0)
        XCTAssertGreaterThan(reused.statistics.reusedComponentCount, 0)
        let replacement = try await service.generate(data, scopeID: secondScope)
        XCTAssertEqual(replacement.statistics.reusedComponentCount, 0)
        try await service.reset(scopeID: firstScope)
        let stillCurrent = try await service.generate(data, scopeID: secondScope)
        XCTAssertGreaterThan(stillCurrent.statistics.reusedComponentCount, 0)
        try await service.reset(scopeID: secondScope)
        let reset = try await service.generate(data, scopeID: secondScope)
        XCTAssertEqual(reset.statistics.reusedComponentCount, 0)
    }

    func testCacheDegradationIsSeparateFromPrimaryGenerationFailure() async throws {
        let service = EditorPreviewService(maximumCachePayloadBytes: 1)
        let scope = UUID()
        let result = try await service.generate(archive(), scopeID: scope)
        XCTAssertNotNil(result.mesh)
        XCTAssertEqual(result.statistics.outcome, .bypassed)
        XCTAssertEqual(result.statistics.cacheIssue?.status, 4)
        do {
            _ = try await service.generate(Data(), scopeID: scope)
            XCTFail("A malformed document must retain its primary error")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, 1)
            XCTAssertTrue(error.message.contains("nonempty"))
        }
        let recovered = try await service.generate(archive(), scopeID: scope)
        XCTAssertNotNil(recovered.mesh)
        XCTAssertEqual(recovered.statistics.reusedComponentCount, 0)
    }

    func testCancelledRequestDoesNotCreateAnInvalidConfiguredSession() async throws {
        let service = EditorPreviewService(maximumCachePayloadBytes: -1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.generate(Data(), scopeID: UUID())
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must precede native session creation")
        } catch is CancellationError {
            try await service.reset(scopeID: UUID())
        }
    }

    func testConcurrentScopesKeepNativeJobsSerial() async throws {
        let data = try archive()
        let result = try await MeshGenerationSession().generateSourcedIndexed(data: data)
        let worker = YieldingMeshGenerator(result: result)
        let service = EditorPreviewService(makeSession: { _ in worker })
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    _ = try await service.generate(data, scopeID: UUID())
                }
            }
            try await group.waitForAll()
        }
        let maximumConcurrentJobs = await worker.maximumConcurrentJobs
        XCTAssertEqual(maximumConcurrentJobs, 1, "One editor must not overlap native jobs across replacement scopes")
    }

    func testInFlightCancellationIsRelayedToTheQueuedOperation() async throws {
        let data = try archive()
        let result = try await MeshGenerationSession().generateSourcedIndexed(data: data)
        let worker = SuspendedMeshGenerator(result: result)
        let service = EditorPreviewService(makeSession: { _ in worker })
        let operation = Task { try await service.generate(data, scopeID: UUID()) }
        defer {
            operation.cancel()
            Task { await worker.finish() }
        }
        for _ in 0..<300 {
            if await worker.hasStarted { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let hasStarted = await worker.hasStarted
        XCTAssertTrue(hasStarted, "The backend must be suspended before cancellation")
        operation.cancel()
        await worker.finish()
        do {
            _ = try await operation.value
            XCTFail("In-flight cancellation must reach the queued operation")
        } catch is CancellationError {
            // The backend deliberately completes; the service must discard its result.
        }
    }

    private func archive() throws -> Data {
        let xml = """
            <canvas originX='.5' originY='.5' originZ='.5'><nodes><node id='{00001000-0000-4000-8000-000000001000}'
            partId='{00000100-0000-4000-8000-000000000100}' x='.5' y='.5' z='.5' radius='.2'/></nodes><edges/>
            <parts><part id='{00000100-0000-4000-8000-000000000100}'/></parts><components>
            <component id='{00000200-0000-4000-8000-000000000200}' linkDataType='partId'
            linkData='{00000100-0000-4000-8000-000000000100}'/></components></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
    }
}

private actor YieldingMeshGenerator: EditorMeshGenerating {
    let result: SourcedMeshGenerationResult
    private var activeJobs = 0
    private(set) var maximumConcurrentJobs = 0

    init(result: SourcedMeshGenerationResult) { self.result = result }
    func generateSourcedIndexed(data: Data, maximumPayloadBytes: Int, maximumSourcePayloadBytes: Int) async throws
        -> SourcedMeshGenerationResult
    {
        activeJobs += 1
        maximumConcurrentJobs = max(maximumConcurrentJobs, activeJobs)
        for _ in 0..<20 { await Task.yield() }
        activeJobs -= 1
        return result
    }
    func generateIndexed(data: Data, maximumPayloadBytes: Int) async throws -> MeshGenerationResult {
        throw UnexpectedPreviewBackendCall.fallback
    }
    func reset() async throws {}
}

private actor SuspendedMeshGenerator: EditorMeshGenerating {
    let result: SourcedMeshGenerationResult
    private var continuation: CheckedContinuation<SourcedMeshGenerationResult, Never>?
    private(set) var hasStarted = false
    init(result: SourcedMeshGenerationResult) { self.result = result }
    func generateSourcedIndexed(data: Data, maximumPayloadBytes: Int, maximumSourcePayloadBytes: Int) async throws
        -> SourcedMeshGenerationResult
    {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            hasStarted = true
        }
    }
    func generateIndexed(data: Data, maximumPayloadBytes: Int) async throws -> MeshGenerationResult {
        throw UnexpectedPreviewBackendCall.fallback
    }
    func reset() async throws {}
    func finish() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private enum UnexpectedPreviewBackendCall: Error { case fallback }
