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
                    do {
                        _ = try await service.generate(data, scopeID: UUID())
                    } catch is CancellationError {
                        // Superseded waiting previews are deliberately retired.
                    } catch EditorPreviewSchedulingError.previewBacklog {
                        // Distinct documents beyond the fixed waiting capacity receive a typed rejection.
                    }
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

    func testReplacedWaitingPreviewCancelsBeforeActiveGenerationFinishes() async throws {
        let data = try archive()
        let result = try await MeshGenerationSession().generateSourcedIndexed(data: data)
        let worker = SuspendedMeshGenerator(result: result)
        let service = EditorPreviewService(makeSession: { _ in worker })
        let scope = UUID()
        let active = Task { try await service.generate(data, scopeID: scope) }
        defer { Task { await worker.finishAll() } }
        for _ in 0..<300 {
            if await worker.hasStarted { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = await worker.hasStarted
        XCTAssertTrue(started)
        let probe = PreviewCancellationProbe()
        let waiting = Task {
            do {
                _ = try await service.generate(data, scopeID: scope)
                probe.completedWithoutCancellation = true
            } catch is CancellationError {
                probe.cancelled = true
            }
        }
        // The actor is free while the controlled backend suspends; give submission a turn.
        try await Task.sleep(for: .milliseconds(30))
        let newest = Task { try await service.generate(data, scopeID: scope) }
        for _ in 0..<100 {
            if probe.cancelled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(probe.cancelled, "Replaced waiting work must return without waiting for active native generation")
        XCTAssertFalse(probe.completedWithoutCancellation)
        await worker.finishAll()
        _ = try await active.value
        _ = try await newest.value
        try await waiting.value
    }

    func testCancelledWaitingPreviewReturnsBeforeActiveGenerationFinishes() async throws {
        let data = try archive()
        let result = try await MeshGenerationSession().generateSourcedIndexed(data: data)
        let worker = SuspendedMeshGenerator(result: result)
        let service = EditorPreviewService(makeSession: { _ in worker })
        let scope = UUID()
        let active = Task { try await service.generate(data, scopeID: scope) }
        defer { Task { await worker.finishAll() } }
        for _ in 0..<300 {
            if await worker.hasStarted { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let probe = PreviewCancellationProbe()
        let waiting = Task {
            do {
                _ = try await service.generate(data, scopeID: scope)
                probe.completedWithoutCancellation = true
            } catch is CancellationError {
                probe.cancelled = true
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        waiting.cancel()
        for _ in 0..<100 {
            if probe.cancelled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(probe.cancelled, "Queued cancellation must not wait for native generation")
        XCTAssertFalse(probe.completedWithoutCancellation)
        await worker.finishAll()
        _ = try await active.value
        try await waiting.value
    }

    func testOldScopeCleanupRunsBeforeLatestWaitingPreview() async throws {
        let data = try archive()
        let result = try await MeshGenerationSession().generateSourcedIndexed(data: data)
        let worker = SuspendedMeshGenerator(result: result)
        let service = EditorPreviewService(makeSession: { _ in worker })
        let firstScope = UUID()
        let active = Task { try await service.generate(data, scopeID: firstScope) }
        defer { Task { await worker.finishAll() } }
        for _ in 0..<300 {
            if await worker.hasStarted { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let newest = Task { try await service.generate(data, scopeID: UUID()) }
        try await Task.sleep(for: .milliseconds(30))
        let reset = Task { try await service.reset(scopeID: firstScope) }
        try await Task.sleep(for: .milliseconds(30))
        await worker.finishAll()
        _ = try await active.value
        _ = try await newest.value
        try await reset.value
        let events = await worker.events
        XCTAssertEqual(events, ["generate", "reset", "generate"])
    }

    func testResetBacklogIsBoundedWithoutRejectingNewestPreview() async throws {
        let data = try archive()
        let result = try await MeshGenerationSession().generateSourcedIndexed(data: data)
        let worker = SuspendedMeshGenerator(result: result)
        let service = EditorPreviewService(makeSession: { _ in worker })
        let scope = UUID()
        let active = Task { try await service.generate(data, scopeID: scope) }
        defer { Task { await worker.finishAll() } }
        for _ in 0..<300 {
            if await worker.hasStarted { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let probe = PreviewCancellationProbe()
        var resets: [Task<Void, any Error>] = []
        for _ in 0..<3 {
            resets.append(
                Task {
                    do {
                        try await service.reset(scopeID: scope)
                    } catch EditorPreviewSchedulingError.resetBacklog {
                        probe.resetBacklogCount += 1
                    }
                })
            try await Task.sleep(for: .milliseconds(30))
        }
        let newest = Task { try await service.generate(data, scopeID: UUID()) }
        for _ in 0..<100 {
            if probe.resetBacklogCount == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(probe.resetBacklogCount, 1, "Cleanup metadata has a fixed bound even while native work suspends")
        await worker.finishAll()
        _ = try await active.value
        let preview = try await newest.value
        XCTAssertNotNil(preview.mesh, "Cleanup overload must not reject the latest document preview")
        for reset in resets { try await reset.value }
    }

    func testResetErrorPreservesOriginalCauseAndAllowsNextPreview() async throws {
        let data = try archive()
        let result = try await MeshGenerationSession().generateSourcedIndexed(data: data)
        let worker = SuspendedMeshGenerator(result: result)
        await worker.failNextReset()
        let service = EditorPreviewService(makeSession: { _ in worker })
        let scope = UUID()
        let active = Task { try await service.generate(data, scopeID: scope) }
        defer { Task { await worker.finishAll() } }
        for _ in 0..<300 {
            if await worker.hasStarted { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let reset = Task { try await service.reset(scopeID: scope) }
        try await Task.sleep(for: .milliseconds(30))
        let newest = Task { try await service.generate(data, scopeID: UUID()) }
        await worker.finishAll()
        _ = try await active.value
        do {
            try await reset.value
            XCTFail("Cleanup must retain its original reported error")
        } catch PreviewResetFailure.expected {
            // This is a Swift backend value error, not native fault injection.
        }
        let preview = try await newest.value
        XCTAssertNotNil(preview.mesh)
    }

    func testCancelledResetStillClearsWaitingPreviewAndCompletesCleanup() async throws {
        let data = try archive()
        let result = try await MeshGenerationSession().generateSourcedIndexed(data: data)
        let worker = SuspendedMeshGenerator(result: result)
        let service = EditorPreviewService(makeSession: { _ in worker })
        let scope = UUID()
        let active = Task { try await service.generate(data, scopeID: scope) }
        defer { Task { await worker.finishAll() } }
        for _ in 0..<300 {
            if await worker.hasStarted { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let probe = PreviewCancellationProbe()
        let waiting = Task {
            do {
                _ = try await service.generate(data, scopeID: scope)
                probe.completedWithoutCancellation = true
            } catch is CancellationError {
                probe.cancelled = true
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        let reset = Task { try await service.reset(scopeID: scope) }
        reset.cancel()
        for _ in 0..<100 {
            if probe.cancelled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(probe.cancelled, "Closing a scope retires its waiting preview promptly")
        await worker.finishAll()
        _ = try await active.value
        try await reset.value
        try await waiting.value
        let events = await worker.events
        XCTAssertEqual(
            events, ["generate", "reset"], "Cleanup survives cancellation and does not generate closed-scope work")
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
    private var shouldFinishAll = false
    private var shouldFailReset = false
    private(set) var events: [String] = []
    init(result: SourcedMeshGenerationResult) { self.result = result }
    func generateSourcedIndexed(data: Data, maximumPayloadBytes: Int, maximumSourcePayloadBytes: Int) async throws
        -> SourcedMeshGenerationResult
    {
        events.append("generate")
        if shouldFinishAll { return result }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            hasStarted = true
        }
    }
    func generateIndexed(data: Data, maximumPayloadBytes: Int) async throws -> MeshGenerationResult {
        throw UnexpectedPreviewBackendCall.fallback
    }
    func failNextReset() { shouldFailReset = true }
    func reset() async throws {
        events.append("reset")
        if shouldFailReset {
            shouldFailReset = false
            throw PreviewResetFailure.expected
        }
    }
    func finishAll() {
        shouldFinishAll = true
        finish()
    }
    func finish() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private enum UnexpectedPreviewBackendCall: Error { case fallback }
private enum PreviewResetFailure: Error { case expected }

@MainActor
private final class PreviewCancellationProbe {
    var cancelled = false
    var completedWithoutCancellation = false
    var resetBacklogCount = 0
}
