import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private enum RecordedPreview: Error, Equatable {
    case completed(UInt8)
    case unexpectedFallback
}

/// Records normal scheduling only; no document is parsed and no engine entry occurs.
private actor GatedScopePreviewBackend: EditorMeshGenerating {
    private var release: CheckedContinuation<Void, Never>?
    private(set) var started: [UInt8] = []
    private(set) var resetCount = 0
    private var active = 0
    private(set) var maximumActive = 0

    func generateSourcedIndexed(data: Data, maximumPayloadBytes: Int, maximumSourcePayloadBytes: Int)
        async throws -> SourcedMeshGenerationResult
    {
        let identifier = data.first ?? 0
        active += 1
        maximumActive = max(maximumActive, active)
        started.append(identifier)
        await withCheckedContinuation { release = $0 }
        active -= 1
        throw RecordedPreview.completed(identifier)
    }

    func generateIndexed(data: Data, maximumPayloadBytes: Int) async throws -> MeshGenerationResult {
        throw RecordedPreview.unexpectedFallback
    }
    func reset() { resetCount += 1 }
    func finish() {
        release?.resume()
        release = nil
    }
}

@MainActor
final class EditorPreviewScopeSchedulingTests: XCTestCase {
    private func submit(_ number: UInt8, scope: UUID, to service: EditorPreviewService)
        -> Task<EditorPreviewResult, any Error>
    {
        Task { try await service.generate(Data([number]), scopeID: scope) }
    }

    private func waitForPending(_ count: Int, service: EditorPreviewService) async throws {
        for _ in 0..<200 {
            if await service.pendingPreviewScopeCount == count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Expected pending scope count \(count)")
        throw RecordedPreview.unexpectedFallback
    }

    private func waitForStarted(_ count: Int, backend: GatedScopePreviewBackend) async throws {
        for _ in 0..<200 {
            if await backend.started.count == count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Expected recorded backend start count \(count)")
        throw RecordedPreview.unexpectedFallback
    }

    private func expectCompletion(_ task: Task<EditorPreviewResult, any Error>, number: UInt8) async {
        do {
            _ = try await task.value
            XCTFail("Recording backend must retain its original completion marker")
        } catch {
            XCTAssertEqual(error as? RecordedPreview, .completed(number))
        }
    }

    private func expectCancellation(_ task: Task<EditorPreviewResult, any Error>) async {
        do {
            _ = try await task.value
            XCTFail("Retired waiting work must be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testOtherDocumentsSurviveReplacementAndKeepFIFOOrder() async throws {
        let backend = GatedScopePreviewBackend()
        let service = EditorPreviewService(makeSession: { _ in backend })
        let firstScope = UUID()
        let active = submit(0, scope: UUID(), to: service)
        try await waitForStarted(1, backend: backend)
        let replaced = submit(1, scope: firstScope, to: service)
        try await waitForPending(1, service: service)
        let other = submit(2, scope: UUID(), to: service)
        try await waitForPending(2, service: service)
        let latest = submit(3, scope: firstScope, to: service)
        await expectCancellation(replaced)
        await backend.finish()
        await expectCompletion(active, number: 0)
        try await waitForStarted(2, backend: backend)
        let following = submit(4, scope: firstScope, to: service)
        try await waitForPending(2, service: service)
        await backend.finish()
        await expectCompletion(latest, number: 3)
        try await waitForStarted(3, backend: backend)
        await backend.finish()
        await expectCompletion(other, number: 2)
        try await waitForStarted(4, backend: backend)
        await backend.finish()
        await expectCompletion(following, number: 4)
        let order = await backend.started
        let maximum = await backend.maximumActive
        XCTAssertEqual(order, [0, 3, 2, 4])
        XCTAssertEqual(maximum, 1)
    }

    func testScopeCapacityAllowsReplacementAndRecoversAfterCancellation() async throws {
        let backend = GatedScopePreviewBackend()
        let service = EditorPreviewService(makeSession: { _ in backend })
        let active = submit(0, scope: UUID(), to: service)
        try await waitForStarted(1, backend: backend)
        let scopes = (0..<8).map { _ in UUID() }
        var pending: [Task<EditorPreviewResult, any Error>] = []
        for index in 0..<8 {
            pending.append(submit(UInt8(index + 1), scope: scopes[index], to: service))
            try await waitForPending(index + 1, service: service)
        }
        do {
            _ = try await service.generate(Data([9]), scopeID: UUID())
            XCTFail("Ninth distinct waiting scope must reject")
        } catch EditorPreviewSchedulingError.previewBacklog {
            XCTAssertFalse(EditorPreviewSchedulingError.previewBacklog.localizedDescription.isEmpty)
        }
        let replacement = submit(10, scope: scopes[0], to: service)
        await expectCancellation(pending[0])
        for task in pending.dropFirst() { task.cancel() }
        for task in pending.dropFirst() { await expectCancellation(task) }
        try await waitForPending(1, service: service)
        await backend.finish()
        await expectCompletion(active, number: 0)
        try await waitForStarted(2, backend: backend)
        await backend.finish()
        await expectCompletion(replacement, number: 10)
        let recovered = submit(11, scope: UUID(), to: service)
        try await waitForStarted(3, backend: backend)
        await backend.finish()
        await expectCompletion(recovered, number: 11)
        let order = await backend.started
        XCTAssertEqual(order, [0, 10, 11])
    }

    func testResetRetiresOnlyItsScopeAndPreservesCleanupOrdering() async throws {
        let backend = GatedScopePreviewBackend()
        let service = EditorPreviewService(makeSession: { _ in backend })
        let activeScope = UUID()
        let retiredScope = UUID()
        let active = submit(0, scope: activeScope, to: service)
        try await waitForStarted(1, backend: backend)
        let retired = submit(1, scope: retiredScope, to: service)
        try await waitForPending(1, service: service)
        let survivor = submit(2, scope: UUID(), to: service)
        try await waitForPending(2, service: service)
        try await service.reset(scopeID: retiredScope)
        await expectCancellation(retired)
        try await waitForPending(1, service: service)
        let reset = Task { try await service.reset(scopeID: activeScope) }
        for _ in 0..<200 {
            if await service.pendingResetCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let pendingResets = await service.pendingResetCount
        XCTAssertEqual(pendingResets, 1, "Observe queued cleanup before releasing active work")
        await backend.finish()
        await expectCompletion(active, number: 0)
        try await reset.value
        try await waitForStarted(2, backend: backend)
        await backend.finish()
        await expectCompletion(survivor, number: 2)
        let order = await backend.started
        let resets = await backend.resetCount
        XCTAssertEqual(order, [0, 2])
        XCTAssertEqual(resets, 1)
    }
}
