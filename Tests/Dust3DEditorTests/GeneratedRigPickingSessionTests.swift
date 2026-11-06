import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest
import simd

@testable import Dust3DEditor
@testable import Dust3DKit
@testable import Dust3DRendering

private func pickingRig() -> GeneratedRig {
    let vertices = [SIMD3<Float>(-1, -1, -0.2), SIMD3(1, -1, -0.2), SIMD3(0, 1, -0.2)].map {
        MeshVertex(position: $0, normal: SIMD3(0, 0, 1), color: .one)
    }
    let joints = ["Root", "Child"].map {
        GeneratedRigJoint(
            name: $0, parentIndex: nil, head: .zero, tail: SIMD3(0, 0, 1), capsuleRadius: 0.1, closingAngle: 0,
            restWorld: [], inverseBind: [])
    }
    return GeneratedRig(
        mesh: Mesh(vertices: vertices, nodeCount: 1, partCount: 1, warning: ""), joints: joints,
        influences: Array(repeating: GeneratedRigInfluences(joints: .init(repeating: .max), weights: .zero), count: 3),
        eyelidsGenerated: false)
}
private func pickingRunsOnMain() -> Bool { Thread.isMainThread }
private actor PickingGate {
    var calls = 0
    var beganOnMain = false
    var pending: [Int: CheckedContinuation<MeshPickResult, Error>] = [:]
    func load(onMain: Bool) async throws -> MeshPickResult {
        calls += 1
        beganOnMain = onMain
        let key = calls
        return try await withCheckedThrowingContinuation { pending[key] = $0 }
    }
    func contains(_ call: Int) -> Bool { pending[call] != nil }
    func finish(_ call: Int, _ result: MeshPickResult) { pending.removeValue(forKey: call)?.resume(returning: result) }
    func fail(_ call: Int) {
        pending.removeValue(forKey: call)?.resume(
            throwing: RigTemplateHierarchyError.invalidMetadata("original hit cause"))
    }
}
@MainActor private final class PickingSnapshotBox {
    var value: EditorSnapshot
    init(_ value: EditorSnapshot) { self.value = value }
}
@MainActor
final class GeneratedRigPickingSessionTests: XCTestCase {
    private let palette = RigTemplatePreviewAppearance(boneColor: .one, selectedBoneColor: .one, ringColor: .one)
    private var input: MeshPickInput {
        MeshPickInput(point: SIMD2(50, 50), size: SIMD2(100, 100), transform: matrix_identity_float4x4)
    }
    private func snapshot() async throws -> EditorSnapshot {
        let document = try Dust3DDocument(
            snapshotXML: Data("<canvas rigType='Snake'><nodes/><edges/><parts/></canvas>".utf8))
        return try await EditorSession().open(data: document.encoded())
    }
    private func make(_ box: PickingSnapshotBox, _ gate: PickingGate) -> GeneratedRigPreviewSession {
        GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in pickingRig() },
            display: GeneratedRigDisplayState.withPicking { rig, _ in
                GeneratedRigDisplayGeometry(
                    mesh: Mesh(
                        vertices: rig.mesh.vertices + rig.mesh.vertices, nodeCount: 1, partCount: 1, warning: ""),
                    skeletonTriangleOwners: [1])
            }, readSnapshot: { box.value }, picker: { _, _, _ in try await gate.load(onMain: pickingRunsOnMain()) })
    }
    private func wait(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<10000 {
            if await condition() { return }
            await Task.yield()
        }
        throw RigTemplateHierarchyError.invalidMetadata("picking did not settle")
    }
    private func start(_ session: GeneratedRigPreviewSession, _ box: PickingSnapshotBox) async throws {
        session.update(
            request: GeneratedRigPreviewRequest(snapshot: box.value), selectedBoneName: "Root", appearance: palette)
        try await wait { session.canPick }
    }
    func testBackgroundHitSelectsCopiedJointWithoutDocumentWriteOrGeneration() async throws {
        let box = PickingSnapshotBox(try await snapshot())
        let original = box.value.document.encoded()
        let gate = PickingGate()
        let session = make(box, gate)
        try await start(session, box)
        let rigRevision = session.currentRevision
        session.pick(input, lease: session.pickingRevision)
        try await wait { await gate.contains(1) }
        XCTAssertTrue(session.isPicking)
        await gate.finish(1, .bone(1))
        try await wait { session.isReady && session.selectedIndex == 1 && !session.isPicking }
        XCTAssertEqual(session.currentRevision, rigRevision)
        XCTAssertEqual(box.value.document.encoded(), original)
        let onMain = await gate.beganOnMain
        XCTAssertFalse(onMain)
        session.stop()
    }
    func testLateHitCannotSurvivePresentationRoundTripOrCameraMovement() async throws {
        let box = PickingSnapshotBox(try await snapshot())
        let gate = PickingGate()
        let session = make(box, gate)
        try await start(session, box)
        let old = session.pickingRevision
        session.pick(input, lease: old)
        try await wait { await gate.contains(1) }
        session.setPresentation(.generatedRest)
        session.setPresentation(.model)
        session.pick(input, lease: old)
        await gate.finish(1, .bone(1))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.selectedIndex, 0)
        XCTAssertFalse(session.isPicking)
        session.pick(input, lease: session.pickingRevision)
        try await wait { await gate.contains(2) }
        XCTAssertTrue(session.cameraState.replaceFromInteraction(OrbitCamera(yaw: 1)))
        await gate.finish(2, .bone(1))
        try await wait { !session.isPicking }
        XCTAssertEqual(session.selectedIndex, 0)
        session.pick(input, lease: session.pickingRevision)
        try await wait { await gate.contains(3) }
        session.cameraState.invalidateProjection()
        await gate.finish(3, .bone(1))
        try await wait { !session.isPicking }
        XCTAssertEqual(session.selectedIndex, 0)
        session.stop()
    }
    func testHiddenBonesAndStoppedWindowRejectLateHits() async throws {
        let box = PickingSnapshotBox(try await snapshot())
        let gate = PickingGate()
        let session = make(box, gate)
        try await start(session, box)
        session.pick(input, lease: session.pickingRevision)
        try await wait { await gate.contains(1) }
        session.showsBones = false
        XCTAssertFalse(session.canPick)
        await gate.finish(1, .bone(1))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.selectedIndex, 0)
        session.showsBones = true
        session.pick(input, lease: session.pickingRevision)
        try await wait { await gate.contains(2) }
        session.stop()
        await gate.finish(2, .bone(1))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(session.currentRig)
        XCTAssertFalse(session.isPicking)
        XCTAssertFalse(session.canPick)
    }
    func testBodyMissAndOriginalFailurePreserveSelectionAndAllowRetry() async throws {
        let box = PickingSnapshotBox(try await snapshot())
        let gate = PickingGate()
        let session = make(box, gate)
        try await start(session, box)
        for (call, result) in [(1, MeshPickResult.body), (2, .miss)] {
            session.pick(input, lease: session.pickingRevision)
            try await wait { await gate.contains(call) }
            await gate.finish(call, result)
            try await wait { !session.isPicking }
            XCTAssertEqual(session.selectedIndex, 0)
        }
        session.pick(input, lease: session.pickingRevision)
        try await wait { await gate.contains(3) }
        await gate.fail(3)
        try await wait { session.pickingError != nil }
        XCTAssertTrue(session.pickingError?.contains("original hit cause") == true)
        XCTAssertTrue(session.isReady)
        session.pick(input, lease: session.pickingRevision)
        try await wait { await gate.contains(4) }
        await gate.finish(4, .bone(1))
        try await wait { session.isReady && session.selectedIndex == 1 }
        XCTAssertNil(session.pickingError)
        session.stop()
    }
    func testSourceReplacementRejectsResultBeforeViewUpdateRuns() async throws {
        let box = PickingSnapshotBox(try await snapshot())
        let gate = PickingGate()
        let session = make(box, gate)
        try await start(session, box)
        session.pick(input, lease: session.pickingRevision)
        try await wait { await gate.contains(1) }
        box.value = try await snapshot()
        await gate.finish(1, .bone(1))
        try await wait { !session.isPicking }
        XCTAssertNil(session.currentRig)
        XCTAssertFalse(session.canPick)
        session.stop()
    }
    func testDefaultPickerSelectsCopiedGeometryWithoutNativeGeneration() async throws {
        let box = PickingSnapshotBox(try await snapshot())
        let original = box.value.document.encoded()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in pickingRig() },
            display: GeneratedRigDisplayState.withPicking { rig, _ in
                GeneratedRigDisplayGeometry(
                    mesh: Mesh(
                        vertices: rig.mesh.vertices + rig.mesh.vertices, nodeCount: 1, partCount: 1, warning: ""),
                    skeletonTriangleOwners: [1])
            }, readSnapshot: { box.value })
        try await start(session, box)
        let revision = session.currentRevision
        let input = MeshPickInput(
            point: SIMD2(50, 50), size: SIMD2(100, 100), transform: session.cameraState.camera.transform(aspect: 1))
        session.pick(input, lease: session.pickingRevision)
        try await wait { session.isReady && session.selectedIndex == 1 && !session.isPicking }
        XCTAssertEqual(session.currentRevision, revision)
        XCTAssertEqual(box.value.document.encoded(), original)
        session.stop()
    }

}
