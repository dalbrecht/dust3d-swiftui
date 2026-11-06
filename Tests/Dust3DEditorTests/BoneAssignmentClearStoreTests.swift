import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct ClearNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class BoneAssignmentClearStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Biped'><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='e1' partId='p' from='a' to='b' boneName='Head'/><edge id='e2' partId='unknown' from='b' to='a' boneName='HairBack3'/><edge id='e3' from='a' to='b' boneName='Other'/></edges><parts><part id='p' locked='true' visible='false'/></parts></canvas>"
                    .utf8))
    }
    private func store() -> EditorStore {
        let blocked = ClearNoNative()
        return EditorStore(
            preview: blocked, materialBaker: blocked, importedMaterialLoader: blocked, sourceMaterialBaker: blocked,
            animationCatalog: blocked)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Global clear did not settle")
    }
    func testActualCapturedFactoryClearsChainOncePreservesPreviewAndOtherWindowAndUndo() async throws {
        let value = store()
        let other = store()
        defer {
            value.stop()
            other.stop()
        }
        let original = try source()
        await value.load(data: original.encoded())
        await other.load(data: original.encoded())
        try await settle(value)
        try await settle(other)
        let snapshot = try XCTUnwrap(value.snapshot)
        let context = RigTemplateBrowserContext(
            hierarchy: try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped")), snapshot: snapshot)
        let target = try XCTUnwrap(context.clearTarget(name: "Head", includeDescendants: true))
        XCTAssertTrue(value.canClearBoneAssignments(target))
        XCTAssertFalse(other.canClearBoneAssignments(target))
        let preview = value.previewRevision
        let material = value.materialViewportRevision
        let camera = value.cameraReset
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        let action = value.clearBoneAssignmentsAction(target)
        action()
        try await settle(value)
        let cleared = try XCTUnwrap(value.snapshot)
        XCTAssertTrue(cleared.edges.filter { ["e1", "e2"].contains($0.id) }.allSatisfy { $0.boneName.isEmpty })
        XCTAssertTrue(try XCTUnwrap(cleared.edges.first { $0.id == "e3" }).hasExactBoneName("Other"))
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(cleared.selectedEdgeIDs, snapshot.selectedEdgeIDs)
        XCTAssertEqual(cleared.selectedIDs, snapshot.selectedIDs)
        XCTAssertEqual(value.previewRevision, preview)
        XCTAssertEqual(value.materialViewportRevision, material)
        XCTAssertEqual(value.cameraReset, camera)
        XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
        action()
        try await settle(value)
        XCTAssertEqual(publications, 1)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(try XCTUnwrap(value.snapshot).canUndo)
        XCTAssertTrue(try XCTUnwrap(value.snapshot).canRedo)
        action()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertTrue(try XCTUnwrap(value.snapshot).canRedo)
        value.redo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), cleared.document.encoded())
    }
    func testInitiallyUnavailableSelectionABAReplacementAndStopNeverRetarget() async throws {
        for change in 0..<3 {
            let value = store()
            defer { value.stop() }
            let original = try source()
            await value.load(data: original.encoded())
            try await settle(value)
            let snapshot = try XCTUnwrap(value.snapshot)
            let target = BoneAssignmentClearTarget(snapshot: snapshot, names: ["Head"])
            let action = value.clearBoneAssignmentsAction(target)
            let missing = value.clearBoneAssignmentsAction(
                BoneAssignmentClearTarget(snapshot: snapshot, names: ["Missing"]))
            switch change {
            case 0:
                value.setLock(.x, isLocked: true)
                try await settle(value)
                value.setLock(.x, isLocked: false)
                try await settle(value)
            case 1:
                await value.load(data: original.encoded())
                try await settle(value)
            default: value.stop()
            }
            action()
            missing()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(try XCTUnwrap(value.snapshot).canUndo)
        }
    }
}
