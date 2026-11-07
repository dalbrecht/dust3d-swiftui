import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct ProfileKeyboardNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
final class CanvasProfileKeyboardStoreTests: XCTestCase {
    func testFocusCanvasUsesActiveLeaseWithoutChangingProfileSelectionOrSource() async throws {
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: try makeDocument().encoded())
        try await settle(store)
        store.setDualCanvasProfile(true)
        store.plane = .side
        store.selectGraph(nodes: ["a"], edges: ["ab"])
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        let lease = store.canvasProfiles.lease
        var routedTargets: [CanvasProfileFocusTarget] = []
        let action = try XCTUnwrap(
            store.focusCanvasAction { target in
                routedTargets.append(target)
                return true
            })

        XCTAssertTrue(action())
        XCTAssertEqual(routedTargets, [.init(documentIdentity: before.documentIdentity, lease: lease)])
        XCTAssertEqual(store.plane, .side)
        XCTAssertEqual(store.canvasProfiles.lease, lease)
        XCTAssertEqual(store.snapshot?.selectedIDs, before.selectedIDs)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertEqual(store.snapshot?.selectionRevision, before.selectionRevision)
        XCTAssertEqual(store.snapshot?.document.encoded(), before.document.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testFocusCanvasRejectsStalePaneToolAndAcceptedSource() async throws {
        let store = makeStore()
        defer { store.stop() }
        let data = try makeDocument().encoded()
        await store.load(data: data)
        try await settle(store)
        let rejected: @MainActor (CanvasProfileFocusTarget) -> Bool = { _ in
            XCTFail("A stale action reached the native focus boundary")
            return true
        }
        let oldPane = try XCTUnwrap(store.focusCanvasAction(rejected))
        store.plane = .side
        store.plane = .front
        XCTAssertFalse(oldPane())

        let oldTool = try XCTUnwrap(store.focusCanvasAction(rejected))
        store.setMovingOrigin(true)
        XCTAssertFalse(oldTool())
        let focusOrigin = try XCTUnwrap(store.focusCanvasAction { _ in true })
        XCTAssertTrue(focusOrigin())
        XCTAssertTrue(store.isMovingOrigin)
        store.setMovingOrigin(false)
        XCTAssertFalse(oldTool())

        let oldSource = try XCTUnwrap(store.focusCanvasAction(rejected))
        await store.load(data: Data("invalid source".utf8))
        XCTAssertNotNil(store.snapshot)
        XCTAssertFalse(oldSource())
        XCTAssertNil(store.focusCanvasAction(rejected))

        await store.load(data: data)
        try await settle(store)
        XCTAssertFalse(oldSource())
        let current = try XCTUnwrap(store.focusCanvasAction { _ in false })
        XCTAssertFalse(current(), "Propagate the native boundary's declined focus claim")
    }

    func testFocusCanvasRejectsReboundDocumentWindowBeforeReplacementLoad() async throws {
        let store = makeStore()
        defer { store.stop() }
        let id = UUID()
        await store.load(data: try makeDocument().encoded(), fileIdentity: id)
        try await settle(store)
        XCTAssertNil(store.focusCanvasAction(fileIdentity: UUID()) { _ in true })
        var bindingIdentity = id
        let action = try XCTUnwrap(
            store.focusCanvasAction(fileIdentity: id, ownsWindow: { bindingIdentity == id }) { _ in
                XCTFail("The old window action reached native focus after its document binding changed")
                return true
            })
        bindingIdentity = UUID()
        XCTAssertFalse(action())
    }

    func testSwitchRequiresDualLayoutAndExplicitGraphSelectionAndPreservesDocumentState() async throws {
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: try makeDocument().encoded())
        try await settle(store)
        let singleLease = store.canvasProfiles.lease
        XCTAssertFalse(store.canSwitchSelectedCanvasProfile)
        XCTAssertNil(store.switchSelectedCanvasProfile())

        store.setDualCanvasProfile(true)
        XCTAssertFalse(store.canSwitchSelectedCanvasProfile)
        XCTAssertNil(store.switchSelectedCanvasProfile())
        store.selectGraph(nodes: [], edges: ["ab"])
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        XCTAssertTrue(before.selectedIDs.isEmpty)
        XCTAssertEqual(before.selectedEdgeIDs, ["ab"])
        XCTAssertTrue(store.canSwitchSelectedCanvasProfile)
        XCTAssertNil(store.switchSelectedCanvasProfile(expectedLease: singleLease))
        XCTAssertEqual(store.plane, .front)

        let frontLease = store.canvasProfiles.lease
        let sideLease = try XCTUnwrap(store.switchSelectedCanvasProfile(expectedLease: frontLease))
        XCTAssertEqual(store.plane, .side)
        XCTAssertEqual(sideLease, store.canvasProfiles.lease)
        XCTAssertNotEqual(sideLease, frontLease)
        XCTAssertNil(store.switchSelectedCanvasProfile(expectedLease: frontLease))
        let after = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(after.document.encoded(), before.document.encoded())
        XCTAssertEqual(after.documentRevision, before.documentRevision)
        XCTAssertEqual(after.selectionRevision, before.selectionRevision)
        XCTAssertEqual(after.selectedIDs, before.selectedIDs)
        XCTAssertEqual(after.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertEqual(after.canUndo, before.canUndo)
        XCTAssertEqual(after.canRedo, before.canRedo)
    }

    func testSwitchDoesNotInterruptAddOrMoveOrigin() async throws {
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: try makeDocument().encoded())
        try await settle(store)
        store.select("a")
        try await settle(store)
        store.setDualCanvasProfile(true)
        let lease = store.canvasProfiles.lease
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 420, height: 240)
        store.setCanvasContext(projection: projection, width: 420, height: 240, lease: lease)
        XCTAssertTrue(store.canSwitchSelectedCanvasProfile)

        store.beginAddMode()
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertFalse(store.canSwitchSelectedCanvasProfile)
        XCTAssertNil(store.switchSelectedCanvasProfile(expectedLease: lease))
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertEqual(store.canvasProfiles.lease, lease)

        store.cancelAddMode()
        store.setMovingOrigin(true)
        XCTAssertTrue(store.isMovingOrigin)
        XCTAssertFalse(store.canSwitchSelectedCanvasProfile)
        XCTAssertNil(store.switchSelectedCanvasProfile(expectedLease: lease))
        XCTAssertTrue(store.isMovingOrigin)
        XCTAssertEqual(store.canvasProfiles.lease, lease)
        XCTAssertEqual(store.plane, .front)
    }

    private func makeStore() -> EditorStore {
        let stub = ProfileKeyboardNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
    }

    private func makeDocument() throws -> Dust3DDocument {
        let xml = """
            <canvas originX='0.5' originY='0.5' originZ='0.5'>
            <nodes><node id='a' partId='p' x='0.2' y='0.5' z='0.5' radius='0.1'/>
            <node id='b' partId='p' x='0.8' y='0.5' z='0.5' radius='0.1'/></nodes>
            <edges><edge id='ab' partId='p' from='a' to='b'/></edges><parts><part id='p'/></parts>
            <components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Profile keyboard store did not settle")
    }
}
