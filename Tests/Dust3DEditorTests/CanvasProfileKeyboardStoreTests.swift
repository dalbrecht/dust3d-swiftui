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

    func testCapturedNodeRevealDoesNotCrossEditingProfileSwitch() async throws {
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: try makeDocument().encoded())
        try await settle(store)
        store.setDualCanvasProfile(true)
        store.select("a")
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        let context = PartGraphSelectionContext(snapshot: before)
        let frontLease = store.canvasProfiles.lease
        let reveal = try XCTUnwrap(
            store.revealOwningComponentAction(.node("a"), context: context, profileLease: frontLease))

        let sideLease = try XCTUnwrap(store.switchSelectedCanvasProfile(expectedLease: frontLease))
        let previousHint = store.snapshot?.componentRevealHint?.revision
        reveal()
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.componentRevealHint?.revision, previousHint)
        XCTAssertNil(store.revealOwningComponentAction(.node("a"), context: context, profileLease: frontLease))

        let currentReveal = try XCTUnwrap(
            store.revealOwningComponentAction(.node("a"), context: context, profileLease: sideLease))
        currentReveal()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentRevealHint?.componentID, "c")
        XCTAssertEqual(store.snapshot?.selectedIDs, before.selectedIDs)
        XCTAssertEqual(store.snapshot?.document.encoded(), before.document.encoded())
        XCTAssertEqual(store.snapshot?.canUndo, before.canUndo)
    }

    func testRevealAvailabilityDoesNotCarryUniqueOwnerAcrossReplacement() async throws {
        let store = makeStore()
        defer { store.stop() }
        let document = try makeDocument()
        await store.load(data: document.encoded())
        try await settle(store)
        let first = try XCTUnwrap(store.snapshot)
        let reveal = try XCTUnwrap(
            store.revealOwningComponentAction(.node("a"), context: PartGraphSelectionContext(snapshot: first)))
        let xml = String(decoding: document.modelXML, as: UTF8.self)
            .replacingOccurrences(
                of: "</components>", with: "<component id='duplicate' linkData='p' linkDataType='partId'/></components>"
            )
        let replacement = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        await store.load(data: replacement.encoded())
        try await settle(store)
        let context = PartGraphSelectionContext(snapshot: try XCTUnwrap(store.snapshot))
        XCTAssertNil(store.revealOwningComponentAction(.node("a"), context: context))
        XCTAssertNil(store.revealOwningComponentAction(.edge("ab"), context: context))
        reveal()
        XCTAssertFalse(store.isWorking)
        XCTAssertNil(store.snapshot?.componentRevealHint)
        XCTAssertFalse(store.canUndo)
    }

    func testEdgeSidebarActionsRejectReplacedSourceAndSubtractOnlyTheirEdge() async throws {
        let store = makeStore()
        defer { store.stop() }
        let document = try makeDocument()
        await store.load(data: document.encoded(), fileIdentity: UUID())
        try await settle(store)
        let first = try XCTUnwrap(store.snapshot)
        let stale = store.edgeSidebarSelectionAction("ab", context: PartGraphSelectionContext(snapshot: first))

        await store.load(data: document.encoded(), fileIdentity: UUID())
        try await settle(store)
        store.select("a")
        try await settle(store)
        let second = try XCTUnwrap(store.snapshot)
        XCTAssertNotEqual(second.documentIdentity, first.documentIdentity)
        let current = store.edgeSidebarSelectionAction("ab", context: PartGraphSelectionContext(snapshot: second))
        let preview = store.previewRevision

        stale(.add)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        current(.add)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a"])

        stale(.subtract)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        current(.subtract)
        try await settle(store)
        let removed = store.snapshot?.selectionRevision
        current(.subtract)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a"])
        XCTAssertEqual(store.snapshot?.selectionRevision, removed)
        XCTAssertEqual(store.snapshot?.document.encoded(), second.document.encoded())
        XCTAssertEqual(store.previewRevision, preview)
        XCTAssertFalse(store.canUndo)
    }

    func testEdgeSidebarSelectAllKeepsReadonlyInspectionAndUsesRigEligibility() async throws {
        let store = makeStore()
        defer { store.stop() }
        let xml = """
            <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='0.1'/>
            <node id='b' partId='p' x='1' y='0' z='0' radius='0.1'/>
            <node id='c' partId='locked' x='0' y='1' z='0' radius='0.1'/>
            <node id='d' partId='locked' x='1' y='1' z='0' radius='0.1'/></nodes>
            <edges><edge id='ab' from='a' to='b' partId='p'/><edge id='cd' from='c' to='d' partId='locked'/></edges>
            <parts><part id='p'/><part id='locked' locked='true'/></parts></canvas>
            """
        let document = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        await store.load(data: document.encoded())
        try await settle(store)
        store.select("a")
        try await settle(store)
        let ordinary = try XCTUnwrap(store.edgeSidebarSelectAllTarget)
        XCTAssertTrue(store.canSelectAllSidebarEdges(ordinary))
        store.selectAllSidebarEdges(ordinary)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab", "cd"])

        store.setRigEdgeSelection(true)
        let rig = try XCTUnwrap(store.edgeSidebarSelectAllTarget)
        XCTAssertTrue(store.canSelectAllSidebarEdges(rig))
        store.selectAllSidebarEdges(rig)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testEdgeSidebarSelectAllRejectsRetainedSelectionModeAndSourceTargets() async throws {
        let store = makeStore()
        defer { store.stop() }
        let document = try makeDocument()
        await store.load(data: document.encoded())
        try await settle(store)
        let beforeMode = try XCTUnwrap(store.edgeSidebarSelectAllTarget)
        store.setRigEdgeSelection(true)
        store.setRigEdgeSelection(false)
        XCTAssertFalse(store.canSelectAllSidebarEdges(beforeMode))

        let beforeSelection = try XCTUnwrap(store.edgeSidebarSelectAllTarget)
        store.select("a")
        try await settle(store)
        XCTAssertFalse(store.canSelectAllSidebarEdges(beforeSelection))

        let beforeSource = try XCTUnwrap(store.edgeSidebarSelectAllTarget)
        await store.load(data: document.encoded())
        try await settle(store)
        XCTAssertFalse(store.canSelectAllSidebarEdges(beforeSource))
        for stale in [beforeMode, beforeSelection, beforeSource] { store.selectAllSidebarEdges(stale) }
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertFalse(store.canUndo)
    }

    func testEdgeSidebarFocusHasNoSelectAllWhenRigHasNoEligibleRows() async throws {
        let store = makeStore()
        defer { store.stop() }
        let document = try makeDocument().applying(.setPartState(id: "p", property: .locked, value: true))
        await store.load(data: document.encoded())
        try await settle(store)
        store.setRigEdgeSelection(true)

        let target = try XCTUnwrap(store.edgeSidebarSelectAllTarget)
        XCTAssertFalse(store.canSelectAllSidebarEdges(target))
        store.selectAllSidebarEdges(target)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
    }

    func testEditableGeometryActionRejectsRetainedToolAndSource() async throws {
        let store = makeStore()
        defer { store.stop() }
        let document = try makeDocument()
        await store.load(data: document.encoded())
        try await settle(store)
        let oldTool = try XCTUnwrap(store.selectEditableGeometryAction())
        store.setMovingOrigin(true)
        XCTAssertNil(store.selectEditableGeometryAction())
        store.setMovingOrigin(false)
        oldTool()
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])

        let oldSource = try XCTUnwrap(store.selectEditableGeometryAction())
        await store.load(data: document.encoded())
        try await settle(store)
        oldSource()
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])

        let current = try XCTUnwrap(store.selectEditableGeometryAction())
        current()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a", "b"])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.canUndo)
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
