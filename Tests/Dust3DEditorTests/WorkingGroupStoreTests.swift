import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct WorkingGroupNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor
final class WorkingGroupStoreTests: XCTestCase {
    func testDestinationSurvivesSelectionAndDoesNotLeakAcrossWindowsOrLoads() async throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><components><component id='first' name='First'/><component id='second'/></components></canvas>"
                    .utf8))
        let store = makeStore()
        let other = makeStore()
        defer {
            store.stop()
            other.stop()
        }
        await store.load(data: original.encoded())
        await other.load(data: original.encoded())
        store.selectComponent("first")
        try await settle(store)
        let selected = try XCTUnwrap(store.snapshot)
        store.workingGroupAction(.group("first"), snapshot: selected)()
        XCTAssertEqual(store.addPlacementDestination, .group("first"))
        XCTAssertEqual(other.addPlacementDestination, .selection)
        XCTAssertFalse(store.canUndo)

        store.selectComponent("second")
        try await settle(store)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 300)
        store.setCanvasContext(projection: projection, width: 500, height: 300)
        store.beginAddMode()
        let mode = store.addModeID
        let point = CanvasPoint(x: 200, y: 150)
        store.updateAddPointer(at: point, modeID: mode)
        store.placeAddNode(at: point, modeID: mode)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentTree.rows.filter { $0.component.partID != nil }.count, 1)
        XCTAssertEqual(
            store.snapshot?.componentTree.rows.first { $0.component.partID != nil }?.component.parentID, "first")
        XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(store.addPlacementDestination, .group("first"))
        XCTAssertFalse(store.canUndo)

        store.addNode(newPart: true)
        try await settle(store)
        XCTAssertEqual(
            store.snapshot?.componentTree.rows.first { $0.component.partID != nil }?.component.parentID, "first")
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())

        await store.load(data: original.encoded())
        XCTAssertEqual(store.addPlacementDestination, .selection)
        store.workingGroupAction(.group("first"), snapshot: selected)()
        XCTAssertEqual(store.addPlacementDestination, .selection)
    }

    func testRootChoiceInvalidatesRetainedActionsAndActiveAddMode() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data("<canvas><components><component id='group'/></components></canvas>".utf8))
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.selectComponent("group")
        try await settle(store)
        let snapshot = try XCTUnwrap(store.snapshot)
        let retained = store.workingGroupAction(.group("group"), snapshot: snapshot)
        retained()
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 300)
        store.setCanvasContext(projection: projection, width: 500, height: 300)
        store.beginAddMode()
        let oldMode = store.addModeID
        let point = CanvasPoint(x: 200, y: 150)
        store.updateAddPointer(at: point, modeID: oldMode)
        store.workingGroupAction(.documentRoot, snapshot: snapshot)()
        retained()
        XCTAssertEqual(store.addPlacementDestination, .documentRoot)
        XCTAssertFalse(store.isAddingNodes)
        store.placeAddNode(at: point, modeID: oldMode)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testRemovingWorkingGroupRetiresTheGhostWithoutRootFallback() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data("<canvas><components><component id='group'/></components></canvas>".utf8))
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.selectComponent("group")
        try await settle(store)
        let snapshot = try XCTUnwrap(store.snapshot)
        store.workingGroupAction(.group("group"), snapshot: snapshot)()
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 300)
        store.setCanvasContext(projection: projection, width: 500, height: 300)
        store.beginAddMode()
        let oldMode = store.addModeID
        let point = CanvasPoint(x: 200, y: 150)
        store.updateAddPointer(at: point, modeID: oldMode)
        XCTAssertNotNil(store.addGhostPoint)

        store.componentDeletionAction(ComponentDeletionTarget(snapshot: snapshot))()
        try await settle(store)
        XCTAssertTrue(store.snapshot?.componentTree.rows.isEmpty == true)
        XCTAssertEqual(store.addPlacementDestination, .documentRoot)
        XCTAssertFalse(store.isAddingNodes)
        let afterDeletion = store.snapshot?.document.encoded()
        store.placeAddNode(at: point, modeID: oldMode)
        XCTAssertEqual(store.snapshot?.document.encoded(), afterDeletion)

        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(store.addPlacementDestination, .documentRoot)
        XCTAssertFalse(store.canUndo)
    }

    private func makeStore() -> EditorStore {
        let stub = WorkingGroupNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Working group store did not settle")
    }
}
