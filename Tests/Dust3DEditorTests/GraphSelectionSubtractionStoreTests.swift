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
        let crossing = projection.point(for: .init(x: 0.35, y: 0.5, z: 0.5))
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
        XCTAssertEqual(publications, 0)
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
        XCTAssertNil(store.lassoSelectionAction(projection: projection, canvas: canvas, lease: nil))
        store.setCanvasUsesLasso(true)
        let stale = try XCTUnwrap(store.lassoSelectionAction(projection: projection, canvas: canvas, lease: nil))
        let center = projection.point(for: .init(x: 0.5, y: 0, z: 0))
        var lasso = CanvasLasso()
        for (x, y) in [(-5.0, -5.0), (5, -5), (5, 5), (-5, 5)] {
            lasso.append(.init(x: center.x + x, y: center.y + y))
        }
        store.setCanvasUsesLasso(false)
        store.setCanvasUsesLasso(true)
        stale(lasso, .subtract)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])

        let select = try XCTUnwrap(store.lassoSelectionAction(projection: projection, canvas: canvas, lease: nil))
        let calls = await counter.calls
        select(lasso, .subtract)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a", "b"])
        XCTAssertEqual(store.snapshot?.selectionRevision, before.selectionRevision + 1)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertEqual(store.snapshot?.previewIdentity, before.previewIdentity)
        XCTAssertFalse(store.canUndo)
        let afterCalls = await counter.calls
        XCTAssertEqual(afterCalls, calls)
    }

}
