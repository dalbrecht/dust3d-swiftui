import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct ContextNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

private actor ContextPreviewCounter: EditorPreviewServing {
    var calls = 0
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        calls += 1
        throw CancellationError()
    }
    func reset(scopeID: UUID) async throws {}
}

@MainActor final class GraphSelectionActionStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.4' y='.5' z='.5' radius='.1'/><node id='c' partId='p' x='.6' y='.5' z='.5' radius='.1'/><node id='x' partId='q' x='.8' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='ab' partId='p' from='a' to='b'/><edge id='bc' partId='p' from='b' to='c'/></edges><parts><part id='p'/><part id='q'/></parts><components><component id='cp' linkDataType='partId' linkData='p'/><component id='cq' linkDataType='partId' linkData='q'/></components></canvas>
                """.utf8))
    }
    private func store() -> EditorStore {
        let stub = ContextNoNative()
        return EditorStore(
            preview: ContextPreviewCounter(), materialBaker: stub,
            importedMaterialLoader: stub, sourceMaterialBaker: stub, animationCatalog: stub)
    }
    private func prepareCanvas(_ value: EditorStore) {
        value.setCanvasContext(
            projection: CanvasProjection(bounds: value.bounds, plane: value.plane, width: 400, height: 300),
            width: 400, height: 300)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Context actions did not settle")
    }
    func testContextDeletePublishesOnceWithExactUndoAndIndependentWindow() async throws {
        let original = try source()
        let value = store()
        let other = store()
        defer {
            value.stop()
            other.stop()
        }
        await value.load(data: original.encoded())
        await other.load(data: original.encoded())
        try await settle(value)
        try await settle(other)
        value.select("a")
        other.select("x")
        try await settle(value)
        try await settle(other)
        let target = GraphSelectionActionTarget(snapshot: try XCTUnwrap(value.snapshot), action: .deleteSelection)
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        let action = value.graphSelectionAction(target)
        action()
        try await settle(value)
        let after = try XCTUnwrap(value.snapshot).document.encoded()
        XCTAssertFalse(try XCTUnwrap(value.snapshot).nodes.contains { $0.id == "a" })
        XCTAssertEqual(publications, 1)
        action()
        try await settle(value)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(other.snapshot?.selectedID, "x")
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        value.redo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), after)
    }
    func testCapturedMenuRejectsSelectionAndAddModeABA() async throws {
        let value = store()
        defer { value.stop() }
        await value.load(data: try source().encoded())
        try await settle(value)
        value.select("a")
        try await settle(value)
        let target = GraphSelectionActionTarget(snapshot: try XCTUnwrap(value.snapshot), action: .deleteSelection)
        let oldSelection = value.graphSelectionAction(target)
        value.select("b")
        try await settle(value)
        value.select("a")
        try await settle(value)
        oldSelection()
        try await settle(value)
        XCTAssertFalse(value.canUndo)
        let current = GraphSelectionActionTarget(snapshot: try XCTUnwrap(value.snapshot), action: .deleteSelection)
        let oldMode = value.graphSelectionAction(current)
        prepareCanvas(value)
        value.beginAddMode()
        XCTAssertTrue(value.isAddingNodes)
        value.cancelAddMode()
        oldMode()
        try await settle(value)
        XCTAssertFalse(value.canUndo)
        XCTAssertEqual(value.snapshot?.document.encoded(), try source().encoded())
    }
    func testContextCancellationDiscardsGhostWithoutAnEditAndRejectsOldModeLease() async throws {
        let value = store()
        defer { value.stop() }
        await value.load(data: try source().encoded())
        try await settle(value)
        prepareCanvas(value)
        value.beginAddMode()
        let original = try XCTUnwrap(value.snapshot).document.encoded()
        let oldCancel = value.canvasAddCancellationAction()
        oldCancel()
        XCTAssertFalse(value.isAddingNodes)
        XCTAssertFalse(value.canUndo)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        prepareCanvas(value)
        value.beginAddMode()
        oldCancel()
        XCTAssertTrue(value.isAddingNodes)
        value.canvasAddCancellationAction()()
        XCTAssertFalse(value.isAddingNodes)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }
    func testRigEdgeModeKeepsEdgesLocksAndExactAssignmentUndo() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        value.setLock(.x, isLocked: true)
        try await settle(value)
        value.selectGraph(nodes: ["a"], edges: ["ab"])
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        let oldEpoch = value.rigEdgeSelectionEpoch
        let retiredToggle = value.rigEdgeSelectionToggleAction()
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        value.setRigEdgeSelection(true)
        try await settle(value)
        let active = try XCTUnwrap(value.snapshot)
        XCTAssertTrue(value.isSelectingRigEdges)
        XCTAssertTrue(active.selectedIDs.isEmpty)
        XCTAssertEqual(active.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(active.locks, before.locks)
        XCTAssertEqual(active.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(value.admitsCanvasSelectionInput(epoch: oldEpoch, lease: nil))
        retiredToggle(false)
        XCTAssertTrue(value.isSelectingRigEdges)

        value.select("b")
        value.selectGraph(nodes: ["b"], edges: [], mode: .add)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertTrue(value.snapshot?.selectedIDs.isEmpty == true)
        value.assignBoneNameAction("Spine", target: EdgeBoneAssignmentTarget(snapshot: active))()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.edges.first { $0.id == "ab" }?.boneName, "Spine")
        XCTAssertTrue(value.isSelectingRigEdges)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }

    func testRigEdgeMarqueeKeepsNodePicksAndInferredTransformsOut() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        prepareCanvas(value)
        value.setRigEdgeSelection(true)
        let activeEpoch = value.rigEdgeSelectionEpoch
        XCTAssertTrue(value.admitsCanvasSelectionInput(epoch: activeEpoch, lease: nil))
        let projection = CanvasProjection(bounds: value.bounds, plane: .front, width: 400, height: 300)
        let from = projection.point(for: .init(x: 0.2, y: 0.5, z: 0.5))
        let middle = projection.point(for: .init(x: 0.3, y: 0.5, z: 0.5))
        let endpointAndStroke = CanvasSelectionRectangle(
            from: .init(x: from.x - 2, y: from.y - 2), to: .init(x: middle.x + 2, y: middle.y + 2))
        value.selectMarquee(endpointAndStroke, projection: projection, mode: .replace)
        try await settle(value)
        XCTAssertTrue(value.snapshot?.selectedIDs.isEmpty == true)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertFalse(value.canTransform)
        XCTAssertFalse(value.canAdjustSelectionRadius)
        XCTAssertFalse(value.canPerformCanvasPrecision(.right))
        value.moveSelection(by: .init(x: 1, y: 0, z: 0))
        let second = projection.point(for: .init(x: 0.5, y: 0.5, z: 0.5))
        let crossing = CanvasSelectionRectangle(
            from: .init(x: second.x - 2, y: second.y - 2), to: .init(x: second.x + 2, y: second.y + 2))
        value.selectMarquee(crossing, projection: projection, mode: .add)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab", "bc"])
        value.selectMarquee(endpointAndStroke, projection: projection, mode: .toggle)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["bc"])
        value.selectMarquee(crossing, projection: projection, mode: .subtract)
        try await settle(value)
        XCTAssertTrue(value.snapshot?.selectedEdgeIDs.isEmpty == true)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        value.setRigEdgeSelection(false)
        XCTAssertFalse(value.admitsCanvasSelectionInput(epoch: activeEpoch, lease: nil))
        value.setRigEdgeSelection(true)
        XCTAssertFalse(value.admitsCanvasSelectionInput(epoch: activeEpoch, lease: nil))
        await value.load(data: original)
        XCTAssertFalse(value.isSelectingRigEdges)
    }

    func testRigEdgeHoverMatchesClickEligibilityAndRestoresOrdinaryHover() async throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='.2' y='.3' z='.5' radius='.1'/>
                <node id='b' partId='p' x='.8' y='.3' z='.5' radius='.1'/>
                <node id='c' partId='q' x='.2' y='.7' z='.5' radius='.1'/>
                <node id='d' partId='q' x='.8' y='.7' z='.5' radius='.1'/>
                </nodes><edges>
                <edge id='ab' partId='p' from='a' to='b'/>
                <edge id='cd' partId='q' from='c' to='d'/>
                </edges><parts><part id='p'/><part id='q' locked='true'/></parts></canvas>
                """.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: document.encoded())
        try await settle(value)
        let projection = CanvasProjection(bounds: value.bounds, plane: .front, width: 400, height: 300)
        let endpoint = projection.point(for: .init(x: 0.2, y: 0.3, z: 0.5))
        let lockedMiddle = projection.point(for: .init(x: 0.5, y: 0.7, z: 0.5))

        value.updateCanvasHover(at: endpoint, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .node("a"))
        value.updateCanvasHover(at: lockedMiddle, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .edge("cd"))

        value.setRigEdgeSelection(true)
        value.updateCanvasHover(at: endpoint, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .edge("ab"))
        value.pickEdge(at: endpoint, projection: projection, mode: .replace)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])
        value.updateCanvasHover(at: lockedMiddle, projection: projection)
        XCTAssertNil(value.canvasGraphHover)
        value.pickEdge(at: lockedMiddle, projection: projection, mode: .add)
        XCTAssertFalse(value.isWorking)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])

        value.setRigEdgeSelection(false)
        value.updateCanvasHover(at: endpoint, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .node("a"))
        value.updateCanvasHover(at: lockedMiddle, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .edge("cd"))
    }

    func testContextEntriesContainOnlyAvailableActionsAndPlaceDeleteLast() async throws {
        let value = store()
        defer { value.stop() }
        await value.load(data: try source().encoded())
        try await settle(value)
        value.selectEdge("ab")
        try await settle(value)
        let actions = GraphSelectionMenuActions(store: value)
        XCTAssertEqual(actions.entries.map(\.action), [.insertMidpoints, .reverseEdges, .deleteSelection])
        XCTAssertEqual(actions.entries.last?.action, .deleteSelection)
        prepareCanvas(value)
        value.beginAddMode()
        XCTAssertTrue(GraphSelectionMenuActions(store: value).entries.isEmpty)
        value.cancelAddMode()
        let none = GraphSelectionMenuActions(store: nil)
        XCTAssertTrue(none.entries.isEmpty)
    }
}
