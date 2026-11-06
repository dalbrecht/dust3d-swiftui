import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

private func displayMesh(_ marker: String) -> Mesh {
    let vertex = MeshVertex(position: .zero, normal: SIMD3(0, 0, 1), color: .one)
    return Mesh(vertices: [vertex, vertex, vertex], nodeCount: 1, partCount: 1, warning: marker)
}
private func displayRig() -> GeneratedRig {
    GeneratedRig(mesh: displayMesh("source"), joints: [], influences: [], eyelidsGenerated: false)
}
private func displayThreadMarker() -> String { Thread.isMainThread ? "main" : "background" }
private actor GeneratedDisplayGate {
    var next = 0
    var pending: [Int: CheckedContinuation<Mesh, Error>] = [:]
    func load() async throws -> Mesh {
        next += 1
        let key = next
        return try await withCheckedThrowingContinuation { pending[key] = $0 }
    }
    func contains(_ key: Int) -> Bool { pending[key] != nil }
    func finish(_ key: Int, _ marker: String) {
        pending.removeValue(forKey: key)?.resume(returning: displayMesh(marker))
    }
    func fail(_ key: Int) {
        pending.removeValue(forKey: key)?.resume(
            throwing: RigTemplateHierarchyError.invalidMetadata("original display cause"))
    }
}

@MainActor
final class GeneratedRigDisplayStateTests: XCTestCase {
    private func request(
        rig: UUID = UUID(), name: String = "Root", color: SIMD4<Float> = .one
    ) -> GeneratedRigDisplayRequest {
        GeneratedRigDisplayRequest(
            rigRevision: rig, selectedBoneName: name,
            appearance: RigTemplatePreviewAppearance(boneColor: color, selectedBoneColor: .one, ringColor: .one))
    }
    private func wait(_ key: Int, _ gate: GeneratedDisplayGate) async throws {
        for _ in 0..<10000 {
            if await gate.contains(key) { return }
            await Task.yield()
        }
        throw RigTemplateHierarchyError.invalidMetadata("test display builder did not start")
    }
    func testExactKeysDistinguishUnicodePaletteAndRigEpoch() {
        let rig = UUID()
        let first = request(rig: rig, name: "é")
        let decomposed = request(rig: rig, name: "e\u{301}")
        XCTAssertNotEqual(first, decomposed)
        XCTAssertEqual(Set([first, decomposed]).count, 2)
        XCTAssertEqual(first, request(rig: rig, name: "é"))
        XCTAssertNotEqual(first, request(rig: rig, name: "é", color: SIMD4(0, 1, 1, 1)))
        XCTAssertNotEqual(first, request(name: "é"))
    }
    func testLateCompletionAndRenderErrorsCannotReplaceCurrentDisplay() async throws {
        let gate = GeneratedDisplayGate()
        let state = GeneratedRigDisplayState { _, _ in try await gate.load() }
        let key = request()
        let first = Task { await state.load(key, rig: displayRig()) }
        try await wait(1, gate)
        let obsolete = try XCTUnwrap(state.revision)
        let second = Task { await state.load(key, rig: displayRig()) }
        try await wait(2, gate)
        await gate.finish(2, "current")
        await second.value
        let acceptedRevision = try XCTUnwrap(state.revision)
        await gate.finish(1, "obsolete")
        await first.value
        XCTAssertEqual(state.mesh?.warning, "current")
        XCTAssertEqual(state.acceptedRequest, key)
        XCTAssertEqual(state.meshRevision, 1)
        state.recordRenderFailure("obsolete GPU", revision: obsolete)
        XCTAssertNil(state.error)
        state.recordRenderFailure("current GPU", revision: acceptedRevision)
        XCTAssertEqual(state.error, "current GPU")
    }
    func testPaletteRefreshRetainsMeshButHidesAcceptanceUntilNewOutput() async throws {
        let gate = GeneratedDisplayGate()
        let state = GeneratedRigDisplayState { _, _ in try await gate.load() }
        let rig = UUID()
        let firstKey = request(rig: rig)
        let first = Task { await state.load(firstKey, rig: displayRig()) }
        try await wait(1, gate)
        await gate.finish(1, "first")
        await first.value
        let old = try XCTUnwrap(state.revision)
        let nextKey = request(rig: rig, color: SIMD4(0, 1, 1, 1))
        let second = Task { await state.load(nextKey, rig: displayRig()) }
        try await wait(2, gate)
        XCTAssertEqual(state.mesh?.warning, "first")
        XCTAssertNil(state.acceptedRequest)
        XCTAssertTrue(state.isLoading)
        XCTAssertEqual(state.meshRevision, 1)
        state.recordRenderFailure("old GPU during refresh", revision: old)
        XCTAssertNil(state.error)
        await gate.finish(2, "next")
        await second.value
        XCTAssertEqual(state.acceptedRequest, nextKey)
        XCTAssertEqual(state.mesh?.warning, "next")
        XCTAssertEqual(state.meshRevision, 2)
    }
    func testABARetryRejectsOriginalEpoch() async throws {
        let state = GeneratedRigDisplayState { _, key in displayMesh(key.selectedBoneName) }
        let rig = UUID()
        let key = request(rig: rig, name: "A")
        await state.load(key, rig: displayRig())
        let old = try XCTUnwrap(state.revision)
        await state.load(request(rig: rig, name: "B"), rig: displayRig())
        await state.load(key, rig: displayRig())
        XCTAssertNotEqual(state.revision, old)
        XCTAssertEqual(state.meshRevision, 3)
        state.recordRenderFailure("old A GPU", revision: old)
        XCTAssertNil(state.error)
    }
    func testPrecancelledCallerPreservesPublishedMeshAndCurrentWorker() async throws {
        let gate = GeneratedDisplayGate()
        let state = GeneratedRigDisplayState { _, _ in try await gate.load() }
        let key = request()
        let first = Task { await state.load(key, rig: displayRig()) }
        try await wait(1, gate)
        await gate.finish(1, "published")
        await first.value
        let accepted = state.revision
        let cancelled = Task { await state.load(request(), rig: displayRig()) }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(state.revision, accepted)
        XCTAssertEqual(state.acceptedRequest, key)
        XCTAssertEqual(state.mesh?.warning, "published")
        let second = Task { await state.load(key, rig: displayRig()) }
        try await wait(2, gate)
        let pending = state.revision
        let obsolete = Task { await state.load(request(), rig: displayRig()) }
        obsolete.cancel()
        await obsolete.value
        XCTAssertEqual(state.revision, pending)
        XCTAssertTrue(state.isLoading)
        await gate.finish(2, "healthy")
        await second.value
        XCTAssertEqual(state.mesh?.warning, "healthy")
    }
    func testStopRejectsLateResultAndClearsSurface() async throws {
        let gate = GeneratedDisplayGate()
        let state = GeneratedRigDisplayState { _, _ in try await gate.load() }
        let pending = Task { await state.load(request(), rig: displayRig()) }
        try await wait(1, gate)
        state.stop()
        await gate.finish(1, "late")
        await pending.value
        XCTAssertNil(state.mesh)
        XCTAssertNil(state.request)
        XCTAssertNil(state.acceptedRequest)
        XCTAssertNil(state.revision)
        XCTAssertFalse(state.isLoading)
        state.recordRenderFailure("stopped GPU", revision: UUID())
        XCTAssertNil(state.error)
    }
    func testCallerAndBuilderCancellationDoNotPublish() async throws {
        let gate = GeneratedDisplayGate()
        let state = GeneratedRigDisplayState { _, _ in try await gate.load() }
        let pending = Task { await state.load(request(), rig: displayRig()) }
        try await wait(1, gate)
        pending.cancel()
        await gate.finish(1, "cancelled")
        await pending.value
        XCTAssertNil(state.mesh)
        XCTAssertNil(state.request)
        XCTAssertNil(state.acceptedRequest)
        XCTAssertNil(state.revision)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isLoading)
        let independent = GeneratedRigDisplayState { _, _ in throw CancellationError() }
        await independent.load(request(), rig: displayRig())
        XCTAssertNil(independent.request)
        XCTAssertNil(independent.acceptedRequest)
        XCTAssertNil(independent.revision)
        XCTAssertNil(independent.error)
        XCTAssertFalse(independent.isLoading)
    }
    func testOriginalFailureIsPreservedAndStaleFailureIgnored() async throws {
        let gate = GeneratedDisplayGate()
        let state = GeneratedRigDisplayState { _, _ in try await gate.load() }
        let key = request()
        let first = Task { await state.load(key, rig: displayRig()) }
        try await wait(1, gate)
        let second = Task { await state.load(key, rig: displayRig()) }
        try await wait(2, gate)
        await gate.finish(2, "current")
        await second.value
        await gate.fail(1)
        await first.value
        XCTAssertNil(state.error)
        XCTAssertEqual(state.mesh?.warning, "current")
        let third = Task { await state.load(key, rig: displayRig()) }
        try await wait(3, gate)
        await gate.fail(3)
        await third.value
        XCTAssertTrue(state.error?.contains("original display cause") == true)
        XCTAssertNil(state.acceptedRequest)
        XCTAssertEqual(state.mesh?.warning, "current")
        state.recordRenderFailure("cannot overwrite original cause", revision: try XCTUnwrap(state.revision))
        XCTAssertTrue(state.error?.contains("original display cause") == true)
    }
    func testRetainedMeshKeepsItsRigProvenanceUntilAcceptanceOrStop() async throws {
        let gate = GeneratedDisplayGate()
        let state = GeneratedRigDisplayState { _, _ in try await gate.load() }
        let firstKey = request()
        let nextKey = request()
        let first = Task { await state.load(firstKey, rig: displayRig()) }
        try await wait(1, gate)
        XCTAssertNil(state.meshRigRevision)
        await gate.finish(1, "first")
        await first.value
        XCTAssertEqual(state.meshRigRevision, firstKey.rigRevision)
        let failed = Task { await state.load(nextKey, rig: displayRig()) }
        try await wait(2, gate)
        XCTAssertEqual(state.meshRigRevision, firstKey.rigRevision)
        await gate.fail(2)
        await failed.value
        XCTAssertEqual(state.meshRigRevision, firstKey.rigRevision)
        XCTAssertEqual(state.mesh?.warning, "first")
        let cancelled = Task { await state.load(nextKey, rig: displayRig()) }
        try await wait(3, gate)
        cancelled.cancel()
        await gate.finish(3, "cancelled")
        await cancelled.value
        XCTAssertEqual(state.meshRigRevision, firstKey.rigRevision)
        XCTAssertEqual(state.mesh?.warning, "first")
        let accepted = Task { await state.load(nextKey, rig: displayRig()) }
        try await wait(4, gate)
        await gate.finish(4, "next")
        await accepted.value
        XCTAssertEqual(state.meshRigRevision, nextKey.rigRevision)
        XCTAssertEqual(state.mesh?.warning, "next")
        state.stop()
        XCTAssertNil(state.meshRigRevision)
    }

    #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
        func testDefaultBuilderHandlesCopiedZeroAxisRigWithoutNativeGeneration() async throws {
            let mesh = displayMesh("original warning")
            let rig = GeneratedRig(
                mesh: mesh,
                joints: [
                    GeneratedRigJoint(
                        name: "Root", parentIndex: nil, head: .zero, tail: .zero,
                        capsuleRadius: 0, closingAngle: 0, restWorld: [], inverseBind: [])
                ],
                influences: Array(
                    repeating: GeneratedRigInfluences(joints: .init(repeating: .max), weights: .zero), count: 3),
                eyelidsGenerated: false)
            let state = GeneratedRigDisplayState()
            let key = request()
            await state.load(key, rig: rig)
            XCTAssertNil(state.error)
            XCTAssertEqual(state.acceptedRequest, key)
            XCTAssertEqual(state.meshRigRevision, key.rigRevision)
            XCTAssertEqual(state.mesh?.warning, "original warning")
            XCTAssertEqual(state.mesh?.vertices.count, 3)
            XCTAssertEqual(state.mesh?.vertices.first?.color, SIMD4(0.5, 0.5, 0.5, 0.8))
        }
    #endif

    func testBuilderRunsOffMainAndReceivesCopiedRigAndRequest() async throws {
        let key = request(name: "selected")
        let state = GeneratedRigDisplayState { rig, request in
            displayMesh("\(displayThreadMarker())/\(rig.mesh.warning)/\(request.selectedBoneName)")
        }
        await state.load(key, rig: displayRig())
        XCTAssertEqual(state.mesh?.warning, "background/source/selected")
    }
}
