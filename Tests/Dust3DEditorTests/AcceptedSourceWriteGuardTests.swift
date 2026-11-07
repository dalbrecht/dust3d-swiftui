import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct AcceptedSourceNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
private final class AcceptedSourceClipboard: EditorClipboardWriting {
    private(set) var writes = 0

    func write(_ data: Data, snapshotXML: Data) throws {
        writes += 1
    }
}

@MainActor
final class AcceptedSourceWriteGuardTests: XCTestCase {
    func testFailedReplacementPreservesRetainedPreviewAndRejectsEditsAndSelection() async throws {
        let source = try document()
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: source.encoded(), fileIdentity: UUID())
        store.select("a")
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        var published: [Data] = []
        store.onDocumentChanged = { published.append($0) }

        await store.load(data: Data("invalid archive".utf8), fileIdentity: UUID())
        let loadError = try XCTUnwrap(store.errorMessage)
        XCTAssertFalse(store.canSave)
        XCTAssertFalse(store.canPickGraph)
        XCTAssertFalse(store.canDeleteGraphSelection)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 400, height: 400)
        store.setCanvasContext(projection: projection, width: 400, height: 400)
        XCTAssertFalse(store.canBeginAddMode)
        XCTAssertFalse(store.canPerformCanvasPrecision(.left))
        XCTAssertNil(store.beginComponentDrag(grabbedID: "cp"))
        store.select("b")
        try await settle(store)
        store.deleteSelection()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, ["a"])
        XCTAssertEqual(store.snapshot?.selectionRevision, before.selectionRevision)
        XCTAssertEqual(store.snapshot?.documentIdentity, before.documentIdentity)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(store.snapshot?.previewIdentity, before.previewIdentity)
        XCTAssertFalse(store.canUndo)
        XCTAssertTrue(published.isEmpty)
        XCTAssertEqual(store.errorMessage, loadError)
    }

    func testFailedReplacementRejectsCutAndNilFileIdentityCanResumeEditing() async throws {
        let source = try document()
        let store = makeStore()
        defer { store.stop() }
        let pasteboard = AcceptedSourceClipboard()
        await store.load(data: source.encoded(), fileIdentity: UUID())
        store.select("a")
        try await settle(store)
        XCTAssertTrue(store.canCutNodes)
        var published: [Data] = []
        store.onDocumentChanged = { published.append($0) }

        await store.load(data: Data("invalid archive".utf8))
        let loadError = try XCTUnwrap(store.errorMessage)
        XCTAssertFalse(store.canCutNodes)
        store.copyNodes(cut: true, to: pasteboard)
        try await settle(store)
        XCTAssertEqual(pasteboard.writes, 0)
        XCTAssertTrue(published.isEmpty)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(store.errorMessage, loadError)

        XCTAssertTrue(store.canCopyNodes)
        store.copyNodes(to: pasteboard)
        try await settle(store)
        XCTAssertEqual(pasteboard.writes, 1)
        XCTAssertEqual(store.errorMessage, loadError)

        await store.load(data: source.encoded())
        XCTAssertTrue(store.canSave)
        store.select("b")
        try await settle(store)
        store.copyNodes(cut: true, to: pasteboard)
        try await settle(store)
        XCTAssertEqual(pasteboard.writes, 2)
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(store.snapshot?.nodes.map(\.id), ["a"])
        XCTAssertTrue(store.canUndo)
        XCTAssertNil(store.errorMessage)

        store.stop()
        XCTAssertFalse(store.canSave)
        XCTAssertFalse(store.canCutNodes)
    }

    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='ab' partId='p' from='a' to='b'/></edges><parts><part id='p'/></parts><components><component id='cp' linkDataType='partId' linkData='p'/></components></canvas>
                """.utf8))
    }

    private func makeStore() -> EditorStore {
        let stub = AcceptedSourceNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Store operation did not settle")
    }
}
