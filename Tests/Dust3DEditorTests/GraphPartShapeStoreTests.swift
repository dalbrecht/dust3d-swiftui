import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct GraphPartShapeNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
final class GraphPartShapeStoreTests: XCTestCase {
    func testShapeActionRequiresAcceptedSourceAndPreservesGraphSelection() async throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes>
                <parts><part id='p' chamfered='future'/></parts></canvas>
                """.utf8))
        let stub = GraphPartShapeNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: document.encoded())
        store.selectGraph(nodes: ["a"], edges: [])
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        let target = GraphPartShapeTarget(snapshot: before)
        XCTAssertTrue(store.canEditGraphPartShape(target))
        store.setGraphPartShape(.roundedEnds, value: true, target: target)
        try await settle(store)
        let after = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(after.parts.first?.modifierValue(.roundedEnds), true)
        XCTAssertNil(after.parts.first?.modifierValue(.chamfer))
        XCTAssertEqual(after.selectedIDs, before.selectedIDs)
        XCTAssertTrue(store.canUndo)

        let retained = GraphPartShapeTarget(snapshot: after)
        var writes = 0
        store.onDocumentChanged = { _ in writes += 1 }
        await store.load(data: Data("invalid archive".utf8), fileIdentity: UUID())
        XCTAssertFalse(store.canEditGraphPartShape(retained))
        store.setGraphPartShape(.chamfer, value: true, target: retained)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.document.encoded(), after.document.encoded())
        XCTAssertEqual(writes, 0)
    }

    func testRetainedMirrorActionRejectsFailedReplacementAndCurrentSourceUndoesExactly() async throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes><parts><part id='p'/></parts></canvas>"
                    .utf8))
        let stub = GraphPartShapeNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: document.encoded())
        store.selectPart("p")
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        let target = PartMirrorTarget(snapshot: before, partID: "p")
        XCTAssertTrue(store.canEditPartMirror(target))
        let retained = store.partMirrorAction(true, target: target)
        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }

        await store.load(data: Data("invalid archive".utf8), fileIdentity: UUID())
        XCTAssertEqual(store.snapshot?.documentIdentity, before.documentIdentity)
        XCTAssertFalse(store.canEditPartMirror(target))
        retained()
        XCTAssertFalse(store.isWorking)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), before.document.encoded())
        XCTAssertFalse(store.canUndo)
        XCTAssertTrue(writes.isEmpty)

        await store.load(data: document.encoded())
        store.selectPart("p")
        try await settle(store)
        let current = try XCTUnwrap(store.snapshot)
        let currentTarget = PartMirrorTarget(snapshot: current, partID: "p")
        XCTAssertTrue(store.canEditPartMirror(currentTarget))
        retained()
        XCTAssertFalse(store.isWorking)
        store.partMirrorAction(true, target: currentTarget)()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.parts.first?.xMirrored, true)
        XCTAssertEqual(writes.count, 1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), current.document.encoded())
        XCTAssertFalse(store.canUndo)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Graph part shape store did not settle")
    }
}
