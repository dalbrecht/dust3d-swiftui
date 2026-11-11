import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Dust3DRendering
import Foundation
import XCTest

@testable import Dust3DEditor

private struct CanvasWheelZoomNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading
{
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    { throw CancellationError() }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    { throw CancellationError() }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}

@MainActor private final class WheelPreviewVisibility {
    var visible = true
}

@MainActor final class CanvasPreviewWheelZoomTests: XCTestCase {
    private func setup() async throws -> (EditorStore, Data) {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas originX='.5' originY='.5' originZ='.5'>
                <nodes><node id='n' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes>
                <parts><part id='p'/></parts></canvas>
                """.utf8)
        ).encoded()
        let stub = CanvasWheelZoomNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
        await store.load(data: original)
        return (store, original)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Canvas input did not settle")
    }

    func testPointerRefreshesHitBeforeGraphOrCameraAndBusyRoutesOnlyGraph() {
        let canvas = CanvasPointerView(frame: .init(x: 0, y: 0, width: 400, height: 300))
        let node = CanvasPoint(x: 10, y: 10)
        let blank = CanvasPoint(x: 200, y: 100)
        let input = CanvasWheelInput(verticalDelta: 1)
        var overNode = true
        var graphEdits = 0
        var zooms = 0
        canvas.hover = { overNode = $0 == node }
        canvas.wheel = { _ in
            guard overNode else { return false }
            graphEdits += 1
            return true
        }
        canvas.unhandledWheel = { _ in
            zooms += 1
            return true
        }
        canvas.enabled = true
        XCTAssertTrue(canvas.routeWheel(input, at: blank))
        XCTAssertEqual(graphEdits, 0)
        XCTAssertEqual(zooms, 1)
        XCTAssertTrue(canvas.routeWheel(input, at: node))
        XCTAssertEqual(graphEdits, 1)
        XCTAssertEqual(zooms, 1)

        canvas.enabled = false
        canvas.wheelWhileDisabled = { true }
        canvas.tracksHoverWhileDisabled = true
        XCTAssertFalse(canvas.routeWheel(input, at: blank))
        XCTAssertTrue(canvas.routeWheel(input, at: node))
        XCTAssertEqual(graphEdits, 2)
        XCTAssertEqual(zooms, 1)
    }

    func testOptInBlankWheelUsesOnlyVisibleCameraAndPreservesEditPrecedence() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        var steps: [Int] = []
        let camera = EditorPreviewCameraActions(
            canMove: true, move: { _ in XCTFail("Used discrete camera command") }, fit: {},
            wheelZoom: { steps.append($0) })
        let up = CanvasWheelInput(verticalDelta: 4)
        XCTAssertFalse(store.canvasPreviewWheelAction(lease: nil, camera: camera)(up))
        store.setCanvasWheelZoomEnabled(true)
        let wheel = store.canvasPreviewWheelAction(lease: nil, camera: camera)
        XCTAssertTrue(wheel(up))
        XCTAssertTrue(wheel(up))
        XCTAssertTrue(wheel(.init(verticalDelta: -2)))
        XCTAssertEqual(steps, [1, 1, -1])
        XCTAssertFalse(wheel(.init(verticalDelta: 0)))
        XCTAssertFalse(wheel(.init(verticalDelta: 2, modifiers: .command)))
        XCTAssertFalse(wheel(.init(verticalDelta: 2, momentumPhase: .changed)))
        store.setHoveredNode("n")
        XCTAssertFalse(wheel(up))
        store.setHoveredNode(nil)
        store.select("n")
        try await settle(store)
        XCTAssertFalse(store.canvasPreviewWheelAction(lease: nil, camera: camera)(up))
        XCTAssertEqual(steps, [1, 1, -1])
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testDragKeepsGraphSelectionAndRetiresWhenTheVisibleCameraOrPaneChanges() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        store.select("n")
        try await settle(store)
        store.setDualCanvasProfile(true)
        let frontLease = store.canvasProfiles.lease
        let visibility = WheelPreviewVisibility()
        var motions: [SIMD2<Float>] = []
        let camera = EditorPreviewCameraActions(
            canMove: true, isCurrent: { visibility.visible }, move: { _ in }, fit: {},
            beginDrag: {
                (
                    update: { delta, _ in
                        motions.append(delta)
                        return true
                    },
                    end: {}
                )
            })
        let front = try XCTUnwrap(store.canvasPreviewDragAction(lease: frontLease, camera: camera)?())
        XCTAssertTrue(front.update(.init(4, 2), false))
        visibility.visible = false
        XCTAssertFalse(front.update(.init(5, 3), false))
        visibility.visible = true
        let sideLease = try XCTUnwrap(store.activateCanvasCompanion(plane: .side, expectedLease: frontLease))
        XCTAssertFalse(front.update(.init(8, 5), true))
        let side = try XCTUnwrap(store.canvasPreviewDragAction(lease: sideLease, camera: camera)?())
        XCTAssertTrue(side.update(.init(2, 9), true))
        XCTAssertEqual(motions, [SIMD2(4, 2), SIMD2(2, 9)])
        XCTAssertEqual(store.snapshot?.selectedIDs, ["n"])
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testRetainedWheelCannotCrossPanePreferenceToolOrFailedSource() async throws {
        let (store, _) = try await setup()
        defer { store.stop() }
        let visibility = WheelPreviewVisibility()
        var steps = 0
        let camera = EditorPreviewCameraActions(
            canMove: true, isCurrent: { visibility.visible }, move: { _ in }, fit: {}, wheelZoom: { steps += $0 })
        let up = CanvasWheelInput(verticalDelta: 4)
        store.setCanvasWheelZoomEnabled(true)
        store.setDualCanvasProfile(true)
        let frontLease = store.canvasProfiles.lease
        let front = store.canvasPreviewWheelAction(lease: frontLease, camera: camera)
        let sideLease = try XCTUnwrap(store.activateCanvasCompanion(plane: .side, expectedLease: frontLease))
        XCTAssertFalse(front(up))
        let side = store.canvasPreviewWheelAction(lease: sideLease, camera: camera)
        visibility.visible = false
        XCTAssertFalse(side(up))
        visibility.visible = true
        store.setCanvasWheelZoomEnabled(false)
        store.setCanvasWheelZoomEnabled(true)
        XCTAssertFalse(side(up))
        let beforeTool = store.canvasPreviewWheelAction(lease: sideLease, camera: camera)
        store.setMovingOrigin(true)
        store.setMovingOrigin(false)
        XCTAssertFalse(beforeTool(up))
        let current = store.canvasPreviewWheelAction(lease: sideLease, camera: camera)
        await store.load(data: Data("invalid archive".utf8))
        XCTAssertFalse(current(up))
        XCTAssertEqual(steps, 0)
    }

    func testSelectedRadiusWheelStillClaimsInputBeforeCamera() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 400, height: 300)
        store.setCanvasContext(projection: projection, width: 400, height: 300)
        store.select("n")
        try await settle(store)
        store.setCanvasWheelZoomEnabled(true)
        let camera = EditorPreviewCameraActions(
            canMove: true, move: { _ in }, fit: {}, wheelZoom: { _ in XCTFail("Camera stole a graph edit") })
        let fallback = store.canvasPreviewWheelAction(lease: nil, camera: camera)
        let input = CanvasWheelInput(verticalDelta: 4)
        XCTAssertTrue(store.handleCanvasWheel(input))
        XCTAssertFalse(fallback(input))
        try await settle(store)
        XCTAssertTrue(store.canUndo)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
    }

    func testWheelZoomCounterCoalescesAndDoesNotReplayOnRemount() {
        var input = MeshCameraWheelZoom()
        let initial = input
        input.append(step: 1)
        input.append(step: 1)
        input.append(step: -1)
        input.append(step: 1)
        XCTAssertEqual(input.steps(since: initial), 2)
        XCTAssertEqual(input.steps(since: input), 0)
        XCTAssertEqual(input.steps(since: nil), 0)
        var reset = MeshCameraWheelZoom()
        reset.append(step: -1)
        XCTAssertEqual(reset.steps(since: input), -1)
    }
}
