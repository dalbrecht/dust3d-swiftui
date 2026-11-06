import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit
@testable import Dust3DRendering

private func sessionRig() -> GeneratedRig {
    let vertex = MeshVertex(position: .zero, normal: SIMD3(0, 0, 1), color: .one)
    let joints = ["Root", "Child"].enumerated().map { index, name in
        GeneratedRigJoint(
            name: name, parentIndex: index == 0 ? nil : 0, head: .zero, tail: SIMD3(0, 0, 1),
            capsuleRadius: 0.1, closingAngle: 0, restWorld: [], inverseBind: [])
    }
    return GeneratedRig(
        mesh: Mesh(vertices: [vertex, vertex, vertex], nodeCount: 1, partCount: 1, warning: ""),
        joints: joints,
        influences: Array(repeating: GeneratedRigInfluences(joints: .init(repeating: .max), weights: .zero), count: 3),
        eyelidsGenerated: false)
}
private actor SessionRigGate {
    var calls = 0
    var pending: [Int: CheckedContinuation<GeneratedRig?, Error>] = [:]
    func load() async throws -> GeneratedRig? {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { pending[call] = $0 }
    }
    func contains(_ call: Int) -> Bool { pending[call] != nil }
    func finish(_ call: Int) { pending.removeValue(forKey: call)?.resume(returning: sessionRig()) }
    func fail(_ call: Int) {
        pending.removeValue(forKey: call)?.resume(throwing: RigTemplateHierarchyError.invalidMetadata("source cause"))
    }
}
private actor SessionDisplayAttempts {
    var calls = 0
    func build(_ rig: GeneratedRig) throws -> Mesh {
        calls += 1
        if calls == 1 { throw RigTemplateHierarchyError.invalidMetadata("display cause") }
        return rig.mesh
    }
}
@MainActor private final class SessionSnapshotBox {
    var value: EditorSnapshot
    init(_ value: EditorSnapshot) { self.value = value }
}
@MainActor
final class GeneratedRigPreviewSessionTests: XCTestCase {
    private let palette = RigTemplatePreviewAppearance(boneColor: .one, selectedBoneColor: .one, ringColor: .one)
    private func snapshot() async throws -> EditorSnapshot {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Snake'><nodes><node id='n' partId='p' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='p'/></parts></canvas>"
                    .utf8))
        return try await EditorSession().open(data: document.encoded())
    }
    private func wait(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<10000 {
            if await condition() { return }
            await Task.yield()
        }
        throw RigTemplateHierarchyError.invalidMetadata("session did not settle")
    }
    func testPresentationMovesKeepOneGenerationSelectionAndCamera() async throws {
        let snapshot = try await snapshot()
        let request = GeneratedRigPreviewRequest(snapshot: snapshot)
        let gate = SessionRigGate()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { snapshot })
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        try await wait { await gate.contains(1) }
        await gate.finish(1)
        try await wait { session.isReady }
        let revision = try XCTUnwrap(session.currentRevision)
        session.selectJoint(1, revision: revision)
        try await wait { session.isReady && session.selectedIndex == 1 }
        session.move(.orbitRight, revision: revision)
        let camera = session.cameraState
        let yaw = camera.camera.yaw
        session.setPresentation(.generatedRest)
        session.update(request: request, selectedBoneName: nil, appearance: palette)
        session.setPresentation(.model)
        session.setPresentation(.generatedRest)
        XCTAssertTrue(session.cameraState === camera)
        XCTAssertEqual(camera.camera.yaw, yaw)
        XCTAssertEqual(session.currentRevision, revision)
        XCTAssertEqual(session.selectedIndex, 1)
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
        session.stop()
    }
    func testPaletteAndTemplateChangesReprepareWithoutGeneration() async throws {
        let snapshot = try await snapshot()
        let gate = SessionRigGate()
        let request = GeneratedRigPreviewRequest(snapshot: snapshot)
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { snapshot })
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        session.setTemplateSelection("Child", request: request)
        try await wait { await gate.contains(1) }
        await gate.finish(1)
        try await wait { session.isReady }
        XCTAssertEqual(session.selectedIndex, 1)
        let appearance = RigTemplatePreviewAppearance(boneColor: .zero, selectedBoneColor: .one, ringColor: .one)
        session.update(request: request, selectedBoneName: nil, appearance: appearance)
        try await wait { session.isReady && session.display.request?.appearance == appearance }
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
        session.stop()
    }
    func testSourceReplacementRejectsQueuedActionsAndOldUpdates() async throws {
        let current = SessionSnapshotBox(try await snapshot())
        let firstRequest = GeneratedRigPreviewRequest(snapshot: current.value)
        let gate = SessionRigGate()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { current.value })
        session.update(request: firstRequest, selectedBoneName: "Root", appearance: palette)
        try await wait { await gate.contains(1) }
        await gate.finish(1)
        try await wait { session.isReady }
        let old = try XCTUnwrap(session.currentRevision)
        let presentation = session.presentationRevision
        let oldPointerAllowed = { session.allowsCameraInteraction(revision: old, presentationRevision: presentation) }
        XCTAssertTrue(oldPointerAllowed())
        session.setPresentation(.generatedRest)
        XCTAssertFalse(oldPointerAllowed())
        session.setPresentation(.model)
        current.value = try await snapshot()
        let next = GeneratedRigPreviewRequest(snapshot: current.value)
        session.update(request: next, selectedBoneName: "Child", appearance: palette)
        try await wait { await gate.contains(2) }
        let cameraRevision = session.cameraState.revision
        session.move(.orbitLeft, revision: old)
        session.fit(revision: old)
        session.selectJoint(0, revision: old)
        session.update(request: firstRequest, selectedBoneName: "Root", appearance: palette)
        XCTAssertEqual(session.cameraState.revision, cameraRevision)
        XCTAssertEqual(session.request, next)
        await gate.finish(2)
        try await wait { session.isReady }
        XCTAssertEqual(session.selectedIndex, 1)
        XCTAssertFalse(oldPointerAllowed())
        let latest = try XCTUnwrap(session.currentRevision)
        XCTAssertTrue(
            session.allowsCameraInteraction(revision: latest, presentationRevision: session.presentationRevision))
        session.stop()
        XCTAssertFalse(
            session.allowsCameraInteraction(revision: latest, presentationRevision: session.presentationRevision))
    }
    func testStopRejectsLateResultAndCannotBeReactivatedByOldView() async throws {
        let snapshot = try await snapshot()
        let gate = SessionRigGate()
        let request = GeneratedRigPreviewRequest(snapshot: snapshot)
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { snapshot })
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        try await wait { await gate.contains(1) }
        session.stop()
        await gate.finish(1)
        for _ in 0..<20 { await Task.yield() }
        session.update(request: request, selectedBoneName: "Child", appearance: palette)
        XCTAssertNil(session.request)
        XCTAssertNil(session.generation.rig)
        XCTAssertNil(session.display.mesh)
        XCTAssertFalse(session.isReady)
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
    }
    func testLateViewUpdateCannotReplaceNewerExplicitTemplateSelection() async throws {
        let snapshot = try await snapshot()
        let request = GeneratedRigPreviewRequest(snapshot: snapshot)
        let gate = SessionRigGate()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { snapshot })
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        try await wait { await gate.contains(1) }
        session.setTemplateSelection("Child", request: request)
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        await gate.finish(1)
        try await wait { session.isReady }
        XCTAssertEqual(session.selectedIndex, 1)
        XCTAssertEqual(session.display.acceptedRequest?.selectedBoneName, "Child")
        session.stop()
    }

    func testExplicitTemplateClickClearsGeneratedJointOverrideEvenForSameTemplate() async throws {
        let snapshot = try await snapshot()
        let request = GeneratedRigPreviewRequest(snapshot: snapshot)
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in sessionRig() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { snapshot })
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        try await wait { session.isReady }
        session.selectJoint(1, revision: try XCTUnwrap(session.currentRevision))
        try await wait { session.isReady && session.selectedIndex == 1 }
        session.setTemplateSelection("Root", request: request)
        try await wait { session.isReady }
        XCTAssertEqual(session.selectedIndex, 0)
        session.stop()
    }

    func testTemplateClickBeforeFirstPresentationSeedsNewSource() async throws {
        let snapshot = try await snapshot()
        let request = GeneratedRigPreviewRequest(snapshot: snapshot)
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in sessionRig() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { snapshot })
        session.setTemplateSelection("Child", request: request)
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        try await wait { session.isReady }
        XCTAssertEqual(session.selectedName, "Child")
        session.stop()
    }

    func testGenerationRetryRejectsObsoleteEpochAndPreservesOriginalError() async throws {
        let snapshot = try await snapshot()
        let request = GeneratedRigPreviewRequest(snapshot: snapshot)
        let gate = SessionRigGate()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { snapshot })
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        try await wait { await gate.contains(1) }
        let revision = session.generation.revision
        await gate.fail(1)
        try await wait { session.generation.error != nil }
        XCTAssertTrue(session.generation.error?.contains("source cause") == true)
        session.retryGeneration(request: request, revision: UUID())
        XCTAssertEqual(session.generation.revision, revision)
        session.retryGeneration(request: request, revision: revision)
        try await wait { await gate.contains(2) }
        let latest = session.generation.revision
        session.retryGeneration(request: request, revision: revision)
        XCTAssertEqual(session.generation.revision, latest)
        await gate.finish(2)
        try await wait { session.isReady }
        let calls = await gate.calls
        XCTAssertEqual(calls, 2)
        session.stop()
    }

    func testReturningToSamePresentationDoesNotReviveOldPointerLease() async throws {
        let snapshot = try await snapshot()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in sessionRig() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { snapshot })
        session.update(
            request: GeneratedRigPreviewRequest(snapshot: snapshot), selectedBoneName: "Root", appearance: palette)
        try await wait { session.isReady }
        let revision = try XCTUnwrap(session.currentRevision)
        let presentation = session.presentationRevision
        session.setPresentation(.generatedRest)
        session.setPresentation(.model)
        XCTAssertFalse(session.allowsCameraInteraction(revision: revision, presentationRevision: presentation))
        XCTAssertTrue(
            session.allowsCameraInteraction(revision: revision, presentationRevision: session.presentationRevision))
        session.stop()
    }

    func testDisplayRetryUsesCurrentDisplayEpochWithoutRegeneration() async throws {
        let snapshot = try await snapshot()
        let request = GeneratedRigPreviewRequest(snapshot: snapshot)
        let gate = SessionRigGate()
        let attempts = SessionDisplayAttempts()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in try await attempts.build(rig) }, readSnapshot: { snapshot })
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        XCTAssertFalse(session.cameraState.replaceFromInteraction(OrbitCamera()))
        try await wait { await gate.contains(1) }
        await gate.finish(1)
        try await wait { session.display.error != nil }
        XCTAssertTrue(session.display.error?.contains("display cause") == true)
        let displayRequest = session.desiredDisplay
        let revision = session.display.revision
        session.update(request: request, selectedBoneName: nil, appearance: palette)
        session.retryDisplay(request: nil, revision: revision)
        session.retryDisplay(request: displayRequest, revision: UUID())
        XCTAssertEqual(session.display.revision, revision)
        session.retryDisplay(request: displayRequest, revision: revision)
        try await wait { session.isReady }
        XCTAssertTrue(session.cameraState.replaceFromInteraction(OrbitCamera()))
        let calls = await attempts.calls
        let generations = await gate.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(generations, 1)
        session.stop()
        XCTAssertFalse(session.cameraState.replaceFromInteraction(OrbitCamera()))
    }

    func testWorkspaceRegenerationKeepsExplicitTemplateChoiceForSameDocumentAndRigType() async throws {
        let document = try Dust3DDocument(
            snapshotXML: Data("<canvas rigType='Snake'><nodes/><edges/><parts/></canvas>".utf8))
        let editor = EditorSession()
        let current = SessionSnapshotBox(try await editor.open(data: document.encoded()))
        let gate = SessionRigGate()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { current.value })
        session.update(
            request: GeneratedRigPreviewRequest(snapshot: current.value), selectedBoneName: "Root", appearance: palette)
        try await wait { await gate.contains(1) }
        await gate.finish(1)
        try await wait { session.isReady }
        session.setTemplateSelection("Child", request: GeneratedRigPreviewRequest(snapshot: current.value))
        try await wait { session.isReady && session.selectedName == "Child" }
        current.value = try await editor.apply([.setHeadHasEyelids(true)])
        session.update(
            request: GeneratedRigPreviewRequest(snapshot: current.value), selectedBoneName: nil, appearance: palette)
        try await wait { await gate.contains(2) }
        await gate.finish(2)
        try await wait { session.isReady }
        XCTAssertEqual(session.selectedName, "Child")
        XCTAssertEqual(session.display.acceptedRequest?.selectedBoneName, "Child")
        session.stop()
    }

    func testDifferentDocumentOrRigTypeDoesNotInheritStoredTemplateChoice() async throws {
        for changesType in [true, false] {
            let document = try Dust3DDocument(
                snapshotXML: Data("<canvas rigType='Snake'><nodes/><edges/><parts/></canvas>".utf8))
            let editor = EditorSession()
            let current = SessionSnapshotBox(try await editor.open(data: document.encoded()))
            let session = GeneratedRigPreviewSession(
                generation: GeneratedRigPreviewState { _ in sessionRig() },
                display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { current.value })
            session.update(
                request: GeneratedRigPreviewRequest(snapshot: current.value), selectedBoneName: "Child",
                appearance: palette)
            try await wait { session.isReady }
            XCTAssertEqual(session.selectedName, "Child")
            current.value =
                changesType
                ? try await editor.apply([.setRigType(.bird)]) : try await editor.open(data: document.encoded())
            session.update(
                request: GeneratedRigPreviewRequest(snapshot: current.value), selectedBoneName: nil, appearance: palette
            )
            try await wait { session.isReady }
            XCTAssertEqual(session.selectedName, "")
            XCTAssertNil(session.selectedIndex)
            session.stop()
        }
    }

    func testVisibilityUsesFixedFullStreamWithoutGenerationOrLosingSelection() async throws {
        let snapshot = try await snapshot()
        let request = GeneratedRigPreviewRequest(snapshot: snapshot)
        let gate = SessionRigGate()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in
                Mesh(vertices: rig.mesh.vertices + rig.mesh.vertices, nodeCount: 1, partCount: 1, warning: "")
            }, readSnapshot: { snapshot })
        session.update(request: request, selectedBoneName: "Child", appearance: palette)
        try await wait { await gate.contains(1) }
        await gate.finish(1)
        try await wait { session.isReady }
        let revision = try XCTUnwrap(session.currentRevision)
        let displayRevision = session.display.revision
        let camera = session.cameraState
        session.move(.orbitRight, revision: revision)
        let yaw = camera.camera.yaw
        XCTAssertNil(session.drawRange)
        session.showsModel = false
        XCTAssertEqual(session.drawRange, 0..<3)
        session.showsBones = false
        XCTAssertEqual(session.drawRange, 0..<0)
        XCTAssertFalse(
            session.allowsCameraInteraction(revision: revision, presentationRevision: session.presentationRevision))
        session.showsModel = true
        XCTAssertEqual(session.drawRange, 3..<6)
        XCTAssertEqual(session.display.revision, displayRevision)
        XCTAssertEqual(session.display.mesh?.vertices.count, 6)
        session.showsBones = true
        XCTAssertNil(session.drawRange)
        session.setShowsWeights(false)
        try await wait { session.isReady && session.display.acceptedRequest?.showsWeights == false }
        XCTAssertEqual(session.selectedIndex, 1)
        XCTAssertEqual(session.selectedName, "Child")
        XCTAssertEqual(session.cameraState.camera.yaw, yaw)
        let accepted = session.display.revision
        session.setShowsWeights(false)
        XCTAssertEqual(session.display.revision, accepted)
        session.setShowsWeights(true)
        try await wait { session.isReady && session.display.acceptedRequest?.showsWeights == true }
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
        session.stop()
    }

    func testHierarchyRevealSurvivesRemountWithoutMovingCameraAndRejectsObsoleteOrigins() async throws {
        let initial = try await snapshot()
        let box = SessionSnapshotBox(initial)
        let request = GeneratedRigPreviewRequest(snapshot: initial)
        let gate = SessionRigGate()
        let session = GeneratedRigPreviewSession(
            generation: GeneratedRigPreviewState { _ in try await gate.load() },
            display: GeneratedRigDisplayState { rig, _ in rig.mesh }, readSnapshot: { box.value })
        session.update(request: request, selectedBoneName: "Root", appearance: palette)
        try await wait { await gate.contains(1) }
        await gate.finish(1)
        try await wait { session.isReady }
        let revision = try XCTUnwrap(session.currentRevision)
        session.selectJoint(1, revision: revision)
        try await wait { session.isReady && session.selectedIndex == 1 }
        let disclosure = session.hierarchyDisclosure
        XCTAssertEqual(disclosure.expanded, [0])
        XCTAssertTrue(disclosure.isExpanded)
        let first = try XCTUnwrap(disclosure.reveal)
        let origin = session.presentationRevision
        XCTAssertTrue(session.acceptsHierarchyReveal(first, presentationRevision: origin))
        let camera = session.cameraState
        let transform = camera.camera.transform(aspect: 1)
        session.setHierarchyExpanded(false, index: 0, revision: revision, presentationRevision: origin)
        session.update(request: request, selectedBoneName: nil, appearance: palette)
        XCTAssertTrue(session.hierarchyDisclosure === disclosure)
        XCTAssertFalse(disclosure.expanded.contains(0))
        XCTAssertFalse(session.acceptsHierarchyReveal(first, presentationRevision: origin))
        session.revealSelectedJoint(revision: revision, presentationRevision: origin)
        let second = try XCTUnwrap(disclosure.reveal)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(disclosure.expanded.contains(0))
        session.setPresentation(.generatedRest)
        session.setPresentation(.model)
        XCTAssertFalse(session.acceptsHierarchyReveal(second, presentationRevision: origin))
        let current = session.presentationRevision
        session.revealSelectedJoint(revision: revision, presentationRevision: origin)
        XCTAssertNil(disclosure.reveal)
        session.revealSelectedJoint(revision: revision, presentationRevision: current)
        let third = try XCTUnwrap(disclosure.reveal)
        box.value = try await snapshot()
        XCTAssertFalse(session.acceptsHierarchyReveal(third, presentationRevision: current))
        session.setHierarchyExpanded(false, index: 0, revision: revision, presentationRevision: current)
        XCTAssertTrue(disclosure.expanded.contains(0))
        XCTAssertEqual(session.selectedIndex, nil)
        XCTAssertEqual(camera.camera.transform(aspect: 1), transform)
        XCTAssertEqual(session.request, request)
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
        session.stop()
        XCTAssertNil(disclosure.revision)
    }

}
