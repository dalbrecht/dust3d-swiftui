import AppKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct SubtractionNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

private actor SubtractionPreviewCounter: EditorPreviewServing {
    var calls = 0
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        calls += 1
        throw CancellationError()
    }
    func reset(scopeID: UUID) async throws {}
}

@MainActor final class GraphSelectionSubtractionStoreTests: XCTestCase {
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Selection did not settle")
    }
    func testCopiedModifiersChooseSubtractionBeforeToggleWithoutChangingOtherGestures() {
        XCTAssertEqual(GraphSelectionMode.pointerMode(modifiers: [.command, .option]), .subtract)
        XCTAssertEqual(GraphSelectionMode.pointerMode(modifiers: [.command, .option, .shift]), .subtract)
        XCTAssertEqual(GraphSelectionMode.pointerMode(modifiers: .command), .toggle)
        XCTAssertEqual(GraphSelectionMode.pointerMode(modifiers: .shift), .add)
        XCTAssertEqual(GraphSelectionMode.pointerMode(modifiers: .option), .replace)
        XCTAssertEqual(GraphSelectionMode.pointerMode(modifiers: []), .replace)
    }
    func testSubtractionRemovesOnlySelectedHitsWithoutHistoryOrPreviewGeneration() async throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.5' y='.5' z='.5' radius='.1'/><node id='c' partId='p' x='.8' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='ab' partId='p' from='a' to='b'/><edge id='bc' partId='p' from='b' to='c'/></edges><parts><part id='p'/></parts><components><component id='cp' linkDataType='partId' linkData='p'/></components></canvas>
                """.utf8))
        let counter = SubtractionPreviewCounter()
        let stub = SubtractionNoNative()
        let store = EditorStore(
            preview: counter, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: document.encoded())
        try await settle(store)
        store.selectGraph(nodes: ["a", "b"], edges: ["ab"])
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        let calls = await counter.calls
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        store.selectGraph(nodes: ["a", "c"], edges: ["bc"], mode: .subtract)
        try await settle(store)
        let after = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(after.selectedIDs, ["b"])
        XCTAssertEqual(after.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(after.selectionRevision, before.selectionRevision + 1)
        XCTAssertEqual(after.document.encoded(), before.document.encoded())
        XCTAssertEqual(after.previewIdentity, before.previewIdentity)
        XCTAssertEqual(after.canUndo, before.canUndo)
        XCTAssertEqual(after.canRedo, before.canRedo)
        XCTAssertEqual(publications, 0)
        let afterCalls = await counter.calls
        XCTAssertEqual(afterCalls, calls)
        store.selectGraph(nodes: ["c"], edges: ["bc"], mode: .subtract)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectionRevision, after.selectionRevision)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["b"])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 500)
        let target = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: nil))
        store.activateCanvasNode("b", action: .pointerReplace, target: target)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["b"])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(store.snapshot?.selectionRevision, after.selectionRevision)

        let crossing = projection.point(for: .init(x: 0.35, y: 0.5, z: 0.5))
        store.pickEdge(at: crossing, projection: projection, mode: .replace)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["b"])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(store.snapshot?.selectionRevision, after.selectionRevision)
        store.selectMarquee(
            .init(
                from: .init(x: crossing.x - 2, y: crossing.y - 2),
                to: .init(x: crossing.x + 2, y: crossing.y + 2)), projection: projection, mode: .subtract)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["b"], "Endpoints outside the marquee stay selected")
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [], "A crossing selected edge is removed independently")
        store.pickEdge(
            at: projection.point(for: .init(x: 0.65, y: 0.5, z: 0.5)),
            projection: projection, mode: .subtract)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [], "Clicking an unselected edge never adds it")
        XCTAssertEqual(store.snapshot?.selectedIDs, ["b"])

        let unpickedEdge = projection.point(for: .init(x: 0.65, y: 0.5, z: 0.5))
        store.pickEdge(at: unpickedEdge, projection: projection, mode: .replace)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["bc"])
        store.pickEdge(at: .init(x: -500, y: -500), projection: projection, mode: .replace)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])

        store.selectGraph(nodes: ["a", "b"], edges: ["ab"])
        try await settle(store)
        let explicitTarget = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: nil))
        store.activateCanvasNode("b", action: .selection(.replace), target: explicitTarget)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["b"])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        let pointerTarget = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: nil))
        store.activateCanvasNode("c", action: .pointerReplace, target: pointerTarget)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["c"])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertEqual(store.snapshot?.document.encoded(), before.document.encoded())
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(publications, 0)
    }
    private func sidebarStore(includeEdge: Bool = false) async throws -> (EditorStore, Data) {
        let extraNode = includeEdge ? "<node id='e' partId='q' x='1' y='1' z='0' radius='.1'/>" : ""
        let edges = includeEdge ? "<edges><edge id='be' partId='q' from='b' to='e'/></edges>" : ""
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' name='Arm' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' name='Arm' partId='q' x='1' y='0' z='0' radius='.1'/>
                <node id='c' name='Hidden Arm' partId='r' x='2' y='0' z='0' radius='.1'/>
                <node id='d' name='Disabled Arm' partId='s' x='3' y='0' z='0' radius='.1'/>
                \(extraNode)
                </nodes>\(edges)<parts>
                <part id='p' name='Frame' locked='true'/><part id='q' name='Support'/>
                <part id='r' visible='false'/><part id='s' disabled='true'/>
                </parts></canvas>
                """.utf8))
        let stub = SubtractionNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        await store.load(data: source.encoded())
        try await settle(store)
        return (store, source.encoded())
    }

    func testCanvasNodeSidebarSearchPreservesSourceOrderAndDistinguishesDuplicateTitles() async throws {
        let (store, _) = try await sidebarStore()
        defer { store.stop() }
        let request = try XCTUnwrap(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        let rows = request.rows(matching: "  ")
        XCTAssertEqual(rows.map(\.id), ["a", "b", "c", "d"])
        XCTAssertNotEqual(rows[0].accessibilityLabel, rows[1].accessibilityLabel)
        XCTAssertTrue(rows[0].accessibilityLabel.contains("Frame"))
        XCTAssertEqual(request.rows(matching: " fRaMe ARM ").map(\.id), ["a"])
        XCTAssertEqual(request.rows(matching: "support").map(\.id), ["b"])
        XCTAssertEqual(request.rows(matching: "Hidden").map(\.id), ["c"])
        XCTAssertTrue(rows[2].accessibilityLabel.contains("Hidden"))
        XCTAssertTrue(rows[3].accessibilityLabel.contains("Disabled"))
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)
    }

    func testCanvasNodeSidebarDisplaysOnlyByteExactOwnerLabels() throws {
        let composed = "caf\u{e9}"
        let decomposed = "cafe\u{301}"
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='exact' partId='\(composed)' x='0' y='0' z='0' radius='.1'/>
                <node id='alias' partId='\(decomposed)' x='1' y='0' z='0' radius='.1'/>
                </nodes><parts><part id='\(composed)' name='Exact owner'/></parts></canvas>
                """.utf8))
        let snapshot = try EditorState(document: source).snapshot
        let rows = CanvasNodeSidebarRow.rows(in: snapshot)
        XCTAssertEqual(rows.map(\.id), ["exact", "alias"])
        XCTAssertEqual(rows.first?.partTitle, "Exact owner")
        XCTAssertNil(rows.last?.partTitle)
    }

    func testCanvasNodeSidebarSelectsOnlyDisplayedRowsAndKeepsArchiveAndHistory() async throws {
        let (store, source) = try await sidebarStore()
        defer { store.stop() }
        let request = try XCTUnwrap(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        XCTAssertFalse(store.selectCanvasSidebarNodes(["c"], matching: "frame", in: request))
        XCTAssertFalse(store.selectCanvasSidebarNodes(["missing"], matching: "", in: request))
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)
        XCTAssertTrue(store.selectCanvasSidebarNodes(["a", "b"], matching: "arm", in: request))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a", "b"])
        XCTAssertFalse(store.selectCanvasSidebarNodes([], matching: "frame", in: request))
        let selected = try XCTUnwrap(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        XCTAssertFalse(store.selectCanvasSidebarNodes([], matching: "hidden", in: selected))
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a", "b"])
        XCTAssertTrue(store.selectCanvasSidebarNodes([], matching: "frame", in: selected))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["b"])
        let deselected = try XCTUnwrap(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        XCTAssertTrue(store.selectCanvasSidebarNodes(["c"], matching: "hidden", in: deselected))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["c"])
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertFalse(store.canUndo)
    }

    func testCanvasNodeSidebarSelectAllReplacesOutsidePicksAndRejectsEmptyOrStaleResults() async throws {
        let (store, source) = try await sidebarStore(includeEdge: true)
        defer { store.stop() }
        store.selectGraph(nodes: ["a", "b"], edges: ["be"])
        try await settle(store)
        let presentation = try XCTUnwrap(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        XCTAssertFalse(store.selectAllCanvasSidebarNodes(matching: "no matching node", in: presentation))
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a", "b"])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["be"])
        XCTAssertTrue(store.selectAllCanvasSidebarNodes(matching: "frame", in: presentation))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a"])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertFalse(store.selectAllCanvasSidebarNodes(matching: "support", in: presentation))
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertFalse(store.canUndo)
    }

    func testCanvasNodeSidebarRejectsRetainedProfileToolAndFailedSource() async throws {
        let (store, source) = try await sidebarStore()
        defer { store.stop() }
        store.setDualCanvasProfile(true)
        let front = try XCTUnwrap(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        store.plane = .side
        XCTAssertFalse(store.selectCanvasSidebarNodes(["a"], matching: "", in: front))
        XCTAssertNil(store.canvasNodeSidebarPresentation(profileLease: front.profileLease))

        let beforeTool = try XCTUnwrap(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        store.setRigEdgeSelection(true)
        XCTAssertNil(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        store.setRigEdgeSelection(false)
        XCTAssertFalse(store.selectCanvasSidebarNodes(["a"], matching: "", in: beforeTool))

        let beforeFailure = try XCTUnwrap(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        await store.load(data: Data("not a DS3".utf8))
        XCTAssertNil(store.canvasNodeSidebarPresentation(profileLease: store.canvasProfiles.lease))
        XCTAssertFalse(store.selectCanvasSidebarNodes(["a"], matching: "", in: beforeFailure))
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)
        XCTAssertFalse(store.canUndo)
    }

    private func nodeSelectionStore() async throws -> (EditorStore, Data) {
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0.4, y: 0.5, z: 0.5), radius: 0.1))
        let stub = SubtractionNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        await store.load(data: document.encoded())
        return (store, document.encoded())
    }

    func testCanvasNodeSelectionCannotInterruptOriginDragOrResumeWithRetiredTarget() async throws {
        let (store, original) = try await nodeSelectionStore()
        defer { store.stop() }
        let old = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: nil))

        store.setMovingOrigin(true)
        let token = UUID()
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 500)
        store.beginOriginDrag(token: token, projection: projection)
        store.updateOriginDrag(token: token, translation: .init(x: 30, y: 40))
        let originPreview = try XCTUnwrap(store.originDragPosition)
        XCTAssertNil(store.canvasNodeSelectionTarget(profileLease: nil))
        for action: CanvasNodeSelectionAction in [
            .selection(.replace), .selection(.add), .selection(.subtract), .wholePart,
        ] {
            store.activateCanvasNode("a", action: action, target: old)
        }
        try await settle(store)
        XCTAssertEqual(store.originDragPosition, originPreview)
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)

        store.cancelOriginDrag()
        store.activateCanvasNode("a", action: .selection(.replace), target: old)
        try await settle(store)
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)
        let current = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: nil))
        store.activateCanvasNode("a", action: .selection(.replace), target: current)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a"])
    }

    func testCanvasNodeSelectionRejectsRetiredRigEdgeEpochAndFailedReplacement() async throws {
        let (store, original) = try await nodeSelectionStore()
        defer { store.stop() }
        let old = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: nil))
        store.setRigEdgeSelection(true)
        try await settle(store)
        XCTAssertTrue(store.isSelectingRigEdges)
        XCTAssertNil(store.canvasNodeSelectionTarget(profileLease: nil))
        store.setRigEdgeSelection(false)
        try await settle(store)
        XCTAssertFalse(store.isSelectingRigEdges)
        store.activateCanvasNode("a", action: .selection(.replace), target: old)
        try await settle(store)
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)

        let beforeFailure = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: nil))
        await store.load(data: Data("not a DS3".utf8))
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertNil(store.canvasNodeSelectionTarget(profileLease: nil))
        store.activateCanvasNode("a", action: .wholePart, target: beforeFailure)
        try await settle(store)
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)
    }

    func testCanvasNodeSelectionRejectsRetiredAddProfileAndDocumentCaptures() async throws {
        let (store, original) = try await nodeSelectionStore()
        defer { store.stop() }
        store.setDualCanvasProfile(true)
        let frontLease = store.canvasProfiles.lease
        let front = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 500)
        store.setCanvasContext(projection: front, width: 500, height: 500, lease: frontLease)
        let beforeAdd = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: frontLease))
        store.beginAddMode()
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertNil(store.canvasNodeSelectionTarget(profileLease: frontLease))
        store.activateCanvasNode("a", action: .wholePart, target: beforeAdd)
        XCTAssertTrue(store.isAddingNodes)
        store.cancelAddMode()
        store.activateCanvasNode("a", action: .wholePart, target: beforeAdd)
        try await settle(store)
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)

        let frontTarget = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: frontLease))
        store.plane = .side
        let sideLease = store.canvasProfiles.lease
        store.activateCanvasNode("a", action: .wholePart, target: frontTarget)
        try await settle(store)
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)
        let sideTarget = try XCTUnwrap(store.canvasNodeSelectionTarget(profileLease: sideLease))
        store.activateCanvasNode("a", action: .wholePart, target: sideTarget)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a"])

        await store.load(data: original)
        store.activateCanvasNode("a", action: .selection(.add), target: sideTarget)
        try await settle(store)
        XCTAssertTrue(store.snapshot?.selectedIDs.isEmpty == true)
    }

    func testCanvasAccessibilityLabelReflectsTheActiveSelectionTool() {
        XCTAssertEqual(
            NodeCanvas.selectionAccessibilityLabel(usesLasso: false, selectsRigEdges: false),
            "Marquee selection canvas")
        XCTAssertEqual(
            NodeCanvas.selectionAccessibilityLabel(usesLasso: true, selectsRigEdges: false),
            "Lasso selection canvas")
        XCTAssertEqual(
            NodeCanvas.selectionAccessibilityLabel(usesLasso: false, selectsRigEdges: true),
            "Bone assignment edge selection canvas")
        XCTAssertEqual(
            NodeCanvas.selectionAccessibilityLabel(usesLasso: true, selectsRigEdges: true),
            "Bone assignment lasso selection canvas")
    }

    func testNativeLassoUsesPressModifiersAndInvalidationRetiresThePath() async throws {
        let view = CanvasPointerView(frame: .init(x: 0, y: 0, width: 400, height: 300))
        view.enabled = true
        let projection = CanvasProjection(bounds: .init(nodes: []), plane: .front, width: 400, height: 300)
        view.lassoCanvas = .init(projection: projection, width: 400, height: 300)

        var preview: CanvasLasso?
        var paths: [CanvasLasso] = []
        var subtracts: [Bool] = []
        var taps = 0
        var rectangleCommits = 0
        view.lassoPreview = { preview = $0?.path }
        view.lassoFinish = { sample in
            preview = nil
            sample.interaction.commit(sample.path) { _ in }
        }
        view.rectangle = { if $0 == nil { preview = nil } }
        view.select = { _, _ in rectangleCommits += 1 }
        view.tap = { _, _ in taps += 1 }
        view.lassoSelection = { mode in
            let plan = CanvasLassoPickPlan(
                projection: projection, nodes: [], edges: [], selected: ([], []), mode: mode, includesNodes: true)
            return CanvasLassoInteraction(
                plan: plan, isCurrent: { true },
                commit: { path, completion in
                    paths.append(path)
                    subtracts.append(mode == .subtract)
                    completion(true)
                })
        }

        func event(
            _ type: NSEvent.EventType, _ x: Double, _ y: Double, modifiers: NSEvent.ModifierFlags = []
        ) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: .init(x: x, y: y), modifierFlags: modifiers,
                    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }

        view.mouseDown(with: try event(.leftMouseDown, 20, 30, modifiers: [.command, .option]))
        view.mouseDragged(with: try event(.leftMouseDragged, 60, 30))
        view.mouseDragged(with: try event(.leftMouseDragged, 60, 60))
        XCTAssertEqual(preview?.points.count, 3)
        view.mouseUp(with: try event(.leftMouseUp, 20, 60))
        XCTAssertNil(preview)
        XCTAssertEqual(paths.map { $0.points.count }, [4])
        XCTAssertEqual(subtracts, [true])

        view.mouseDown(with: try event(.leftMouseDown, 20, 30))
        view.mouseDragged(with: try event(.leftMouseDragged, 60, 30))
        XCTAssertNotNil(preview)
        view.invalidate()
        view.mouseUp(with: try event(.leftMouseUp, 20, 60))
        XCTAssertNil(preview)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(taps, 0)
        XCTAssertEqual(rectangleCommits, 0)

        view.mouseDown(with: try event(.leftMouseDown, 20, 30))
        view.mouseDragged(with: try event(.leftMouseDragged, 60, 30))
        XCTAssertNotNil(preview)
        XCTAssertTrue(view.resignFirstResponder())
        view.mouseDown(with: try event(.leftMouseDown, 20, 30))
        view.mouseUp(with: try event(.leftMouseUp, 20, 30))
        for _ in 0..<20 where preview != nil { await Task.yield() }
        XCTAssertNil(preview)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(taps, 1)
    }

    func testLassoSubtractsCrossingEdgeAndRejectsRetainedModeABA() async throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='1' y='0' z='1' radius='.1'/>
                </nodes><edges><edge id='ab' partId='p' from='a' to='b'/></edges><parts><part id='p'/></parts></canvas>
                """.utf8)
        ).encoded()
        let stub = SubtractionNoNative()
        let counter = SubtractionPreviewCounter()
        let store = EditorStore(
            preview: counter, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: original)
        try await settle(store)
        store.selectGraph(nodes: ["a", "b"], edges: ["ab"])
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 400, height: 300)
        let canvas = ReferenceColorCanvasIdentity(projection: projection, width: 400, height: 300)
        store.setCanvasContext(projection: projection, width: 400, height: 300)
        store.setReferenceColorCanvasContext(projection: projection, width: 400, height: 300)
        XCTAssertNil(store.lassoInteraction(projection: projection, canvas: canvas, lease: nil, mode: .subtract))
        store.setCanvasUsesLasso(true)
        let stale = try XCTUnwrap(
            store.lassoInteraction(projection: projection, canvas: canvas, lease: nil, mode: .subtract))
        let center = projection.point(for: .init(x: 0.5, y: 0, z: 0))
        var lasso = CanvasLasso()
        for (x, y) in [(-5.0, -5.0), (5, -5), (5, 5), (-5, 5)] {
            lasso.append(.init(x: center.x + x, y: center.y + y))
        }
        store.setCanvasUsesLasso(false)
        store.setCanvasUsesLasso(true)
        stale.commit(lasso) { XCTAssertFalse($0) }
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])

        let select = try XCTUnwrap(
            store.lassoInteraction(projection: projection, canvas: canvas, lease: nil, mode: .subtract))
        let calls = await counter.calls
        let feedback = CanvasLassoFeedback()
        feedback.update(.init(path: CanvasLasso(), interaction: select))
        feedback.clear()
        feedback.update(.init(path: lasso, interaction: select))
        for _ in 0..<40 where feedback.picks == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(feedback.picks?.nodes, ["a", "b"])
        XCTAssertEqual(feedback.picks?.edges, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(store.snapshot?.selectionRevision, before.selectionRevision)
        feedback.update(.init(path: CanvasLasso(), interaction: select))
        XCTAssertNil(feedback.picks, "The prior outline's picks must not describe the replacement outline")
        for _ in 0..<40 where feedback.picks == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(feedback.picks?.edges, ["ab"])
        feedback.clear()
        XCTAssertNil(feedback.path)
        XCTAssertNil(feedback.picks)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        feedback.update(.init(path: lasso, interaction: select))
        for _ in 0..<40 where feedback.picks == nil { try await Task.sleep(for: .milliseconds(5)) }
        feedback.finish(.init(path: lasso, interaction: select))
        XCTAssertNil(feedback.path)
        XCTAssertTrue(feedback.isCommitting)
        XCTAssertEqual(feedback.picks?.edges, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        try await settle(store)
        XCTAssertFalse(feedback.isCommitting)
        XCTAssertNil(feedback.picks)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a", "b"])
        XCTAssertEqual(store.snapshot?.selectionRevision, before.selectionRevision + 1)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertEqual(store.snapshot?.previewIdentity, before.previewIdentity)
        XCTAssertFalse(store.canUndo)
        let nodeCenter = projection.point(for: .init(x: 0, y: 0, z: 0))
        let nodeRadius = 0.1 * projection.scale
        let x = nodeCenter.x - nodeRadius + 2
        var nodeLasso = CanvasLasso()
        for (dx, dy) in [(-4.0, -4.0), (0, -4), (0, 4), (-4, 4)] {
            nodeLasso.append(.init(x: x + dx, y: nodeCenter.y + dy))
        }
        let subtractNode = try XCTUnwrap(
            store.lassoInteraction(projection: projection, canvas: canvas, lease: nil, mode: .subtract))
        subtractNode.commit(nodeLasso) { XCTAssertTrue($0) }
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["b"])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertEqual(store.snapshot?.previewIdentity, before.previewIdentity)
        XCTAssertFalse(store.canUndo)
        let afterCalls = await counter.calls
        XCTAssertEqual(afterCalls, calls)
    }

}
