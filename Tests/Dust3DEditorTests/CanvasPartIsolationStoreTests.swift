import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct IsolationNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

private actor IsolationPreviewCounter: EditorPreviewServing {
    var calls = 0
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        calls += 1
        throw CancellationError()
    }
    func reset(scopeID: UUID) async throws {}
}

@MainActor final class CanvasPartIsolationStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='b' partId='q' x='.4' y='.5' z='.5' radius='.1'/><node id='c' partId='r' x='.8' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p'/><part id='q' visible='false' locked='true'/><part id='r' disabled='true'/><part id='orphan' visible='false' locked='true'/></parts><components><component id='g' name='Keep'><component id='cp' linkDataType='partId' linkData='p'/><component id='cq' linkDataType='partId' linkData='q'/></component><component id='cr' linkDataType='partId' linkData='r'/></components><opaque value='preserve'/></canvas>
                """.utf8))
    }
    private func store(_ preview: IsolationPreviewCounter) -> EditorStore {
        let stub = IsolationNoNative()
        return EditorStore(
            preview: preview, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Isolation store did not settle")
    }
    func testIsolationPublishesOnceAndUndoRedoPreserveMeshIdentityAndOtherWindow() async throws {
        let original = try source()
        let counter = IsolationPreviewCounter()
        let value = store(counter)
        let other = store(IsolationPreviewCounter())
        defer {
            value.stop()
            other.stop()
        }
        await value.load(data: original.encoded())
        await other.load(data: original.encoded())
        try await settle(value)
        try await settle(other)
        value.selectComponent("g")
        other.selectPart("r")
        try await settle(value)
        try await settle(other)
        let before = try XCTUnwrap(value.snapshot)
        let calls = await counter.calls
        let otherBefore = try XCTUnwrap(other.snapshot)
        let target = CanvasPartIsolationTarget(snapshot: before, componentID: "g")
        XCTAssertTrue(value.canPerformCanvasPartIsolation(target))
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        let action = value.canvasPartIsolationAction(target)
        action()
        try await settle(value)
        let after = try XCTUnwrap(value.snapshot)
        XCTAssertFalse(try XCTUnwrap(after.parts.first { $0.id == "r" }).isVisible)
        XCTAssertFalse(try XCTUnwrap(after.parts.first { $0.id == "q" }).isVisible)
        XCTAssertTrue(try XCTUnwrap(after.parts.first { $0.id == "q" }).isLocked)
        XCTAssertTrue(try XCTUnwrap(after.parts.first { $0.id == "r" }).isDisabled)
        XCTAssertEqual(after.previewIdentity, before.previewIdentity)
        XCTAssertEqual(after.selectedComponentIDs, before.selectedComponentIDs)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(other.snapshot?.document.encoded(), otherBefore.document.encoded())
        XCTAssertEqual(other.snapshot?.selectedPartID, "r")
        action()
        try await settle(value)
        XCTAssertEqual(publications, 1)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        value.redo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), after.document.encoded())
        let restoredCalls = await counter.calls
        XCTAssertEqual(restoredCalls, calls)
        let show = CanvasPartIsolationTarget(snapshot: try XCTUnwrap(value.snapshot), showAll: true)
        value.canvasPartIsolationAction(show)()
        try await settle(value)
        XCTAssertTrue(try XCTUnwrap(value.snapshot).parts.allSatisfy(\.isVisible))
        XCTAssertEqual(value.snapshot?.previewIdentity, before.previewIdentity)
    }
    func testCapturedActionsRejectSelectionABAReplacementAndInitiallyUnavailableIntent() async throws {
        let value = store(IsolationPreviewCounter())
        defer { value.stop() }
        await value.load(data: try source().encoded())
        try await settle(value)
        value.selectComponent("g")
        try await settle(value)
        let target = CanvasPartIsolationTarget(snapshot: try XCTUnwrap(value.snapshot), componentID: "g")
        let action = value.canvasPartIsolationAction(target)
        value.selectComponent("cr")
        try await settle(value)
        value.selectComponent("g")
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot).document.encoded()
        action()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), before)
        XCTAssertFalse(value.canUndo)
        let invalid = CanvasPartIsolationTarget(snapshot: try XCTUnwrap(value.snapshot), componentID: "missing")
        let invalidAction = value.canvasPartIsolationAction(invalid)
        await value.load(data: try source().encoded())
        try await settle(value)
        action()
        invalidAction()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), before)
        XCTAssertFalse(value.canUndo)
    }
    func testCancelledActorIsolationLeavesSourceHistoryAndPreviewIdentityUnchanged() async throws {
        let session = EditorSession()
        _ = try await session.open(data: source().encoded())
        let before = try await session.selectComponent("g")
        let target = CanvasPartIsolationTarget(snapshot: before, componentID: "g")
        let task = Task { try await session.setCanvasPartIsolation(target: target) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled isolation should not publish")
        } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        let after = try await session.selectComponent("g")
        XCTAssertEqual(after.document.encoded(), before.document.encoded())
        XCTAssertEqual(after.documentRevision, before.documentRevision)
        XCTAssertEqual(after.previewIdentity, before.previewIdentity)
        XCTAssertFalse(after.canUndo)
    }

    func testHideAllAndRestoreAreSingleVisibilityEditsWithoutPreviewGeneration() async throws {
        let original = try source()
        let counter = IsolationPreviewCounter()
        let value = store(counter)
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.select(nil)
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        let calls = await counter.calls
        XCTAssertTrue(before.selectedIDs.isEmpty && before.selectedEdgeIDs.isEmpty)
        XCTAssertNil(before.selectedPartID)
        XCTAssertTrue(before.selectedComponentIDs.isEmpty)
        let target = CanvasPartIsolationTarget.hidingAll(in: before)
        XCTAssertTrue(value.canPerformCanvasPartIsolation(target))
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        value.canvasPartIsolationAction(target)()
        try await settle(value)
        let hidden = try XCTUnwrap(value.snapshot)
        XCTAssertTrue(hidden.parts.allSatisfy { !$0.isVisible })
        XCTAssertEqual(hidden.previewIdentity, before.previewIdentity)
        XCTAssertEqual(publications, 1)
        XCTAssertTrue(try XCTUnwrap(hidden.parts.first { $0.id == "q" }).isLocked)
        XCTAssertTrue(try XCTUnwrap(hidden.parts.first { $0.id == "r" }).isDisabled)
        XCTAssertFalse(CanvasPartIsolationTarget.hidingAll(in: hidden).isAvailable)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        value.redo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), hidden.document.encoded())
        let show = CanvasPartIsolationTarget(snapshot: try XCTUnwrap(value.snapshot), showAll: true)
        value.canvasPartIsolationAction(show)()
        try await settle(value)
        XCTAssertTrue(try XCTUnwrap(value.snapshot).parts.allSatisfy(\.isVisible))
        XCTAssertEqual(value.snapshot?.previewIdentity, before.previewIdentity)
        let finalCalls = await counter.calls
        XCTAssertEqual(finalCalls, calls)
    }

}
