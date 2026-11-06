import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct AssignmentNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class EdgeBoneAssignmentStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='c' partId='q' x='.3' y='.5' z='.5' radius='.1'/><node id='d' partId='q' x='.4' y='.5' z='.5' radius='.1'/><node id='x' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='e1' partId='p' from='a' to='b' boneName='Café'/><edge id='e2' partId='q' from='c' to='d' boneName='Cafe&#769;'/><edge id='e3' partId='p' from='b' to='x' boneName='Other'/></edges><parts><part id='p'/><part id='q'/></parts></canvas>"
                    .utf8))
    }
    private func store() -> EditorStore {
        let blocked = AssignmentNoNative()
        return EditorStore(
            preview: blocked, materialBaker: blocked, importedMaterialLoader: blocked, sourceMaterialBaker: blocked,
            animationCatalog: blocked)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Bone assignment store did not settle")
    }

    func testFactoryAssignClearNoopOriginalErrorsAndExactUndoPreservePreviewAndOtherWindow() async throws {
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
        value.selectGraph(nodes: ["x"], edges: ["e1", "e2"])
        try await settle(value)
        let target = EdgeBoneAssignmentTarget(snapshot: try XCTUnwrap(value.snapshot))
        XCTAssertTrue(value.canAssignBoneName("Root", target: target))
        XCTAssertFalse(other.canAssignBoneName("Root", target: target))
        let preview = value.previewRevision
        let materials = value.materialViewportRevision
        let camera = value.cameraReset
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        let action = value.assignBoneNameAction("Root", target: target)
        action()
        try await settle(value)
        let bound = try XCTUnwrap(value.snapshot?.document.encoded())
        XCTAssertNotEqual(bound, original.encoded())
        XCTAssertTrue(
            try XCTUnwrap(value.snapshot).edges.filter { ["e1", "e2"].contains($0.id) }.allSatisfy {
                $0.hasExactBoneName("Root")
            })
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["x"])
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["e1", "e2"])
        XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
        action()
        try await settle(value)
        XCTAssertEqual(publications, 1)
        let current = EdgeBoneAssignmentTarget(snapshot: try XCTUnwrap(value.snapshot))
        XCTAssertFalse(value.canAssignBoneName("Root", target: current))
        value.assignBoneNameAction("Root", target: current)()
        value.assignBoneNameAction("bad\nname", target: current)()
        try await settle(value)
        XCTAssertEqual(value.errorMessage, EditorStore.message(DocumentError.invalidBoneName))
        XCTAssertEqual(value.snapshot?.document.encoded(), bound)
        XCTAssertEqual(publications, 1)
        value.assignBoneNameAction("", target: current)()
        try await settle(value)
        XCTAssertEqual(publications, 2)
        XCTAssertEqual(value.previewRevision, preview)
        XCTAssertEqual(value.materialViewportRevision, materials)
        XCTAssertEqual(value.cameraReset, camera)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), bound)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
        value.redo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), bound)
    }

    func testRetainedAndUnavailableFactoriesDoNotAcquireLaterSelectionOrSource() async throws {
        for change in 0..<4 {
            let value = store()
            defer { value.stop() }
            let original = try source()
            await value.load(data: original.encoded())
            try await settle(value)
            let unavailable = value.assignBoneNameAction(
                "Wrong", target: EdgeBoneAssignmentTarget(snapshot: try XCTUnwrap(value.snapshot)))
            value.selectGraph(nodes: [], edges: ["e1", "e2"])
            try await settle(value)
            let target = EdgeBoneAssignmentTarget(snapshot: try XCTUnwrap(value.snapshot))
            let action = value.assignBoneNameAction("Wrong", target: target)
            switch change {
            case 0:
                value.selectGraph(nodes: [], edges: ["e3"])
                try await settle(value)
                value.selectGraph(nodes: [], edges: ["e1", "e2"])
                try await settle(value)
            case 1:
                value.setEdgeBoneName("e3", name: "Changed")
                try await settle(value)
                value.undo()
                try await settle(value)
            case 2:
                await value.load(data: original.encoded())
                try await settle(value)
                value.selectGraph(nodes: [], edges: ["e1", "e2"])
                try await settle(value)
            default: value.stop()
            }
            let before = value.snapshot?.document.encoded()
            let redo = value.canRedo
            var publications = 0
            value.onDocumentChanged = { _ in publications += 1 }
            unavailable()
            action()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), before)
            XCTAssertEqual(value.canRedo, redo)
            XCTAssertEqual(publications, 0)
            XCTAssertFalse(value.canAssignBoneName("Wrong", target: target))
        }
    }
}
