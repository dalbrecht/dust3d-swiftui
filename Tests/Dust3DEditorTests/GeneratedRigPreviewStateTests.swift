import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

private func generatedWorkerMarker() -> String { Thread.isMainThread ? "main" : "background" }
private func copiedRig(_ marker: String) -> GeneratedRig {
    let vertex = MeshVertex(position: .zero, normal: SIMD3(0, 0, 1), color: .one)
    let matrix: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    let joint = GeneratedRigJoint(
        name: marker, parentIndex: nil, head: .zero, tail: SIMD3(0, 0, 1), capsuleRadius: 0.1, closingAngle: 0,
        restWorld: matrix, inverseBind: matrix)
    return GeneratedRig(
        mesh: Mesh(vertices: [vertex, vertex, vertex], nodeCount: 1, partCount: 1, warning: ""), joints: [joint],
        influences: Array(repeating: GeneratedRigInfluences(joints: .init(repeating: .max), weights: .zero), count: 3),
        eyelidsGenerated: false)
}
private actor GeneratedPreviewGate {
    var next = 0
    var pending: [Int: CheckedContinuation<GeneratedRig?, Error>] = [:]
    func load() async throws -> GeneratedRig? {
        next += 1
        let key = next
        return try await withCheckedThrowingContinuation { pending[key] = $0 }
    }
    func contains(_ key: Int) -> Bool { pending[key] != nil }
    func finish(_ key: Int, _ marker: String) { pending.removeValue(forKey: key)?.resume(returning: copiedRig(marker)) }
    func fail(_ key: Int) {
        pending.removeValue(forKey: key)?.resume(throwing: RigTemplateHierarchyError.invalidMetadata("original cause"))
    }
}
@MainActor
final class GeneratedRigPreviewStateTests: XCTestCase {
    private func request() async throws -> GeneratedRigPreviewRequest {
        let doc = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Snake'><nodes><node id='n' partId='p' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='p'/></parts></canvas>"
                    .utf8))
        return GeneratedRigPreviewRequest(snapshot: try await EditorSession().open(data: doc.encoded()))
    }
    private func wait(_ key: Int, _ gate: GeneratedPreviewGate) async throws {
        for _ in 0..<10000 {
            if await gate.contains(key) { return }
            await Task.yield()
        }
        throw RigTemplateHierarchyError.invalidMetadata("test loader did not start")
    }
    func testEqualRetryRejectsLateSuccessAndOldGPUError() async throws {
        let gate = GeneratedPreviewGate()
        let state = GeneratedRigPreviewState { _ in try await gate.load() }
        let request = try await self.request()
        let first = Task { await state.load(request) }
        try await wait(1, gate)
        let old = try XCTUnwrap(state.revision)
        let second = Task { await state.load(request) }
        try await wait(2, gate)
        XCTAssertNil(state.rig)
        XCTAssertTrue(state.isLoading)
        await gate.finish(2, "current")
        await second.value
        await gate.finish(1, "old")
        await first.value
        XCTAssertEqual(state.rig?.joints.first?.name, "current")
        state.recordRenderFailure("old GPU", revision: old)
        XCTAssertNil(state.error)
        state.recordRenderFailure("current GPU", revision: try XCTUnwrap(state.revision))
        XCTAssertEqual(state.error, "current GPU")
    }
    func testStopRejectsPendingResultAndDoesNotAffectOtherSurface() async throws {
        let gate = GeneratedPreviewGate()
        let first = GeneratedRigPreviewState { _ in try await gate.load() }
        let other = GeneratedRigPreviewState { _ in copiedRig("other") }
        let request = try await self.request()
        let task = Task { await first.load(request) }
        try await wait(1, gate)
        first.stop()
        await other.load(request)
        await gate.finish(1, "late")
        await task.value
        XCTAssertNil(first.rig)
        XCTAssertNil(first.request)
        XCTAssertNil(first.revision)
        XCTAssertFalse(first.isLoading)
        XCTAssertEqual(other.rig?.joints.first?.name, "other")
    }
    func testCallerCancellationRejectsPublication() async throws {
        let gate = GeneratedPreviewGate()
        let state = GeneratedRigPreviewState { _ in try await gate.load() }
        let request = try await self.request()
        let task = Task { await state.load(request) }
        try await wait(1, gate)
        task.cancel()
        await gate.finish(1, "cancelled")
        await task.value
        XCTAssertNil(state.rig)
        XCTAssertNil(state.error)
        XCTAssertNil(state.revision)
        XCTAssertNil(state.request)
        XCTAssertFalse(state.isLoading)
    }
    func testOriginalFailureEmptyResultAndBackgroundWorker() async throws {
        let request = try await self.request()
        let failure = GeneratedRigPreviewState { _ in throw RigTemplateHierarchyError.invalidMetadata("original cause")
        }
        await failure.load(request)
        XCTAssertTrue(failure.error?.contains("original cause") == true)
        XCTAssertNil(failure.rig)
        let empty = GeneratedRigPreviewState { _ in nil }
        await empty.load(request)
        XCTAssertNil(empty.rig)
        XCTAssertNil(empty.error)
        XCTAssertFalse(empty.isLoading)
        let worker = GeneratedRigPreviewState { _ in copiedRig(generatedWorkerMarker()) }
        await worker.load(request)
        XCTAssertEqual(worker.rig?.joints.first?.name, "background")
        worker.stop()
        worker.recordRenderFailure("ignored", revision: UUID())
        XCTAssertNil(worker.error)
    }
    func testPrecancelledObsoleteCallerPreservesPublishedResult() async throws {
        let state = GeneratedRigPreviewState { _ in copiedRig("healthy") }
        let current = try await self.request()
        await state.load(current)
        let revision = state.revision
        let obsolete = try await self.request()
        let task = Task { await state.load(obsolete) }
        task.cancel()
        await task.value
        XCTAssertEqual(state.request, current)
        XCTAssertEqual(state.revision, revision)
        XCTAssertEqual(state.rig?.joints.first?.name, "healthy")
        XCTAssertNil(state.error)
    }

    func testPrecancelledObsoleteCallerDoesNotCancelCurrentWorker() async throws {
        let gate = GeneratedPreviewGate()
        let state = GeneratedRigPreviewState { _ in try await gate.load() }
        let current = try await self.request()
        let healthy = Task { await state.load(current) }
        try await wait(1, gate)
        let revision = state.revision
        let obsolete = try await self.request()
        let cancelled = Task { await state.load(obsolete) }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(state.request, current)
        XCTAssertEqual(state.revision, revision)
        XCTAssertTrue(state.isLoading)
        await gate.finish(1, "healthy")
        await healthy.value
        XCTAssertEqual(state.rig?.joints.first?.name, "healthy")
    }

    func testIndependentLoaderCancellationClearsOnlyItsOwnRequest() async throws {
        let state = GeneratedRigPreviewState { _ in throw CancellationError() }
        await state.load(try await self.request())
        XCTAssertNil(state.request)
        XCTAssertNil(state.revision)
        XCTAssertNil(state.rig)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isLoading)
    }

    #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
        func testExperimentalDefaultLoaderHandlesNoneWithoutNativeGeneration() async throws {
            let document = try Dust3DDocument(
                snapshotXML: Data(
                    "<canvas rigType='None'><nodes><node id='n' partId='p' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='p'/></parts></canvas>"
                        .utf8))
            let snapshot = try await EditorSession().open(data: document.encoded())
            let state = GeneratedRigPreviewState()
            await state.load(GeneratedRigPreviewRequest(snapshot: snapshot))
            XCTAssertNil(state.rig)
            XCTAssertNil(state.error)
            XCTAssertFalse(state.isLoading)
        }
    #endif

    func testReplacementRejectsLateFailure() async throws {
        let gate = GeneratedPreviewGate()
        let state = GeneratedRigPreviewState { _ in try await gate.load() }
        let request = try await self.request()
        let first = Task { await state.load(request) }
        try await wait(1, gate)
        let second = Task { await state.load(request) }
        try await wait(2, gate)
        await gate.finish(2, "current")
        await second.value
        await gate.fail(1)
        await first.value
        XCTAssertNil(state.error)
        XCTAssertEqual(state.rig?.joints.first?.name, "current")
    }
    func testCameraInteractionRejectsUnpublishedReplacedAndForeignRequests() async throws {
        let gate = GeneratedPreviewGate()
        let state = GeneratedRigPreviewState { _ in try await gate.load() }
        let request = try await self.request()
        let foreign = try await self.request()
        XCTAssertFalse(state.isCurrent(request: request, revision: UUID()))
        let first = Task { await state.load(request) }
        try await wait(1, gate)
        let old = try XCTUnwrap(state.revision)
        XCTAssertFalse(state.isCurrent(request: request, revision: old))
        await gate.finish(1, "first")
        await first.value
        XCTAssertTrue(state.isCurrent(request: request, revision: old))
        XCTAssertFalse(state.isCurrent(request: foreign, revision: old))
        let replacement = Task { await state.load(request) }
        try await wait(2, gate)
        let current = try XCTUnwrap(state.revision)
        XCTAssertFalse(state.isCurrent(request: request, revision: old))
        XCTAssertFalse(state.isCurrent(request: request, revision: current))
        await gate.finish(2, "replacement")
        await replacement.value
        XCTAssertFalse(state.isCurrent(request: request, revision: old))
        XCTAssertTrue(state.isCurrent(request: request, revision: current))
        state.stop()
        XCTAssertFalse(state.isCurrent(request: request, revision: current))
    }

}
