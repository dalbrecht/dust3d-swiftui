import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct BonePresentationNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class BoneEdgePresentationStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Biped'><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='root' partId='p' from='a' to='b' boneName='Root'/><edge id='open' partId='p' from='b' to='a'/><edge id='hidden' partId='q' from='a' to='b'/></edges><parts><part id='p'/><part id='q' visible='false'/></parts></canvas>"
                    .utf8))
    }
    private func store() -> EditorStore {
        let blocked = BonePresentationNoNative()
        return EditorStore(
            preview: blocked, materialBaker: blocked, importedMaterialLoader: blocked, sourceMaterialBaker: blocked,
            animationCatalog: blocked)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Bone edge presentation did not settle")
    }
    func testActualSelectionFactoryClearsHighlightsAndPreservesHistoryPreviewAndOtherWindow() async throws {
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
        value.renamePart("p", name: "temporary")
        try await settle(value)
        value.undo()
        try await settle(value)
        value.selectGraph(nodes: ["a"], edges: ["root"])
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        let target = BoneEdgeOverview(snapshot: before).target(for: .unassigned)
        let hover = value.boneEdgeHoverAction(target, owner: .init(surface: UUID(), row: Data()))
        hover(true)
        XCTAssertEqual(value.highlightedBoneEdgeIDs, ["open", "hidden"])
        XCTAssertTrue(value.canSelectBoneEdges(target))
        XCTAssertFalse(other.canSelectBoneEdges(target))
        let preview = value.previewRevision
        let materials = value.materialViewportRevision
        let camera = value.cameraReset
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        value.boneEdgeSelectionAction(target)()
        try await settle(value)
        let after = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(after.selectedEdgeIDs, ["open"])
        XCTAssertTrue(after.selectedIDs.isEmpty)
        XCTAssertTrue(value.highlightedBoneEdgeIDs.isEmpty)
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertEqual(after.documentRevision, before.documentRevision)
        XCTAssertTrue(after.canRedo)
        XCTAssertFalse(after.canUndo)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(value.previewRevision, preview)
        XCTAssertEqual(value.materialViewportRevision, materials)
        XCTAssertEqual(value.cameraReset, camera)
        XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
        XCTAssertTrue(try XCTUnwrap(other.snapshot).selectedEdgeIDs.isEmpty)
        let zero = BoneEdgeOverview(snapshot: after).target(for: .named("Hips"))
        XCTAssertTrue(value.canSelectBoneEdges(zero))
        value.boneEdgeSelectionAction(zero)()
        try await settle(value)
        XCTAssertTrue(try XCTUnwrap(value.snapshot).selectedEdgeIDs.isEmpty)
        XCTAssertEqual(publications, 0)
    }
    func testHoverOwnersLateExitSourceChangeAndOtherWindowAreIsolatedWithoutMutation() async throws {
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
        let before = try XCTUnwrap(value.snapshot)
        let overview = BoneEdgeOverview(snapshot: before)
        let surface = UUID()
        let ownerA = BoneEdgeHoverOwner(surface: surface, row: Data("unassigned".utf8))
        let ownerB = BoneEdgeHoverOwner(surface: surface, row: Data("Root".utf8))
        let a = value.boneEdgeHoverAction(overview.target(for: .unassigned), owner: ownerA)
        let b = value.boneEdgeHoverAction(overview.target(for: .named("Root")), owner: ownerB)
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        a(true)
        XCTAssertEqual(value.highlightedBoneEdgeIDs, ["open", "hidden"])
        b(true)
        a(false)
        XCTAssertEqual(value.highlightedBoneEdgeIDs, ["root"])
        other.boneEdgeHoverAction(overview.target(for: .named("Root")), owner: ownerB)(true)
        XCTAssertTrue(other.highlightedBoneEdgeIDs.isEmpty)
        let otherTarget = BoneEdgeOverview(snapshot: try XCTUnwrap(other.snapshot)).target(for: .named("Root"))
        other.boneEdgeHoverAction(otherTarget, owner: ownerB)(true)
        value.setLock(.x, isLocked: true)
        try await settle(value)
        XCTAssertTrue(value.highlightedBoneEdgeIDs.isEmpty)
        XCTAssertEqual(other.highlightedBoneEdgeIDs, ["root"])
        let fresh = BoneEdgeOverview(snapshot: try XCTUnwrap(value.snapshot)).target(for: .named("Root"))
        let newest = value.boneEdgeHoverAction(fresh, owner: ownerB)
        newest(true)
        b(false)
        XCTAssertEqual(
            value.highlightedBoneEdgeIDs, ["root"], "Old source exit cannot clear a newer hover on the same row")
        newest(false)
        XCTAssertTrue(value.highlightedBoneEdgeIDs.isEmpty)
        a(true)
        XCTAssertTrue(value.highlightedBoneEdgeIDs.isEmpty)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(value.snapshot?.selectionRevision, before.selectionRevision)
        XCTAssertEqual(publications, 0)
    }
    func testRetainedOrInitiallyUnavailableActionsNeverAcquireABAUndoReplacementOrStoppedIntent() async throws {
        for change in 0..<5 {
            let value = store()
            defer { value.stop() }
            let original = try source()
            await value.load(data: original.encoded())
            try await settle(value)
            let overview = BoneEdgeOverview(snapshot: try XCTUnwrap(value.snapshot))
            let target = overview.target(for: .unassigned)
            let select = value.boneEdgeSelectionAction(target)
            let hover = value.boneEdgeHoverAction(target, owner: .init(surface: UUID(), row: Data()))
            let unavailable = value.boneEdgeSelectionAction(overview.target(for: .named("")))
            hover(true)
            XCTAssertEqual(value.highlightedBoneEdgeIDs, ["open", "hidden"])
            switch change {
            case 0:
                value.selectGraph(nodes: ["a"], edges: ["root"])
                try await settle(value)
                value.selectGraph(nodes: [], edges: [])
                try await settle(value)
            case 1:
                value.setLock(.x, isLocked: true)
                try await settle(value)
                value.setLock(.x, isLocked: false)
                try await settle(value)
            case 2:
                value.renamePart("p", name: "temporary")
                try await settle(value)
                value.undo()
                try await settle(value)
            case 3:
                await value.load(data: original.encoded())
                try await settle(value)
            default: value.stop()
            }
            let before = try XCTUnwrap(value.snapshot)
            select()
            unavailable()
            hover(true)
            try await settle(value)
            let after = try XCTUnwrap(value.snapshot)
            XCTAssertEqual(after.selectedIDs, before.selectedIDs)
            XCTAssertEqual(after.selectedEdgeIDs, before.selectedEdgeIDs)
            XCTAssertEqual(after.selectionRevision, before.selectionRevision)
            XCTAssertEqual(after.document.encoded(), before.document.encoded())
            XCTAssertEqual(after.canRedo, before.canRedo)
            XCTAssertTrue(value.highlightedBoneEdgeIDs.isEmpty)
        }
    }
}
