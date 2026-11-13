import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct GetStartedNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading, ReferenceImageServing
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
    func importImage(url: URL) async throws -> Data { throw CancellationError() }
    func preview(document: Dust3DDocument) async throws -> ReferenceImagePreview { .init(image: nil, changed: false) }
}

@MainActor final class EditorGetStartedTests: XCTestCase {
    private func makeStore() -> EditorStore {
        let stub = GetStartedNoNative()
        return EditorStore(
            referenceImages: stub, preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
    }

    func testOpenComposeAndDrawFirstNodeDoNotWriteBeforeCommit() async throws {
        let store = makeStore()
        defer { store.stop() }
        let file = UUID()
        let original = Dust3DDocument.emptyArchive()
        await store.load(data: original, fileIdentity: file)
        store.setCanvasContext(
            projection: CanvasProjection(bounds: store.bounds, plane: store.plane, width: 400, height: 300),
            width: 400, height: 300)
        let actions = try XCTUnwrap(EditorGetStartedActions(store: store, fileIdentity: file))
        var opens = 0
        var presented: ReferenceCompositionTarget?
        var writes = 0
        store.onDocumentChanged = { _ in writes += 1 }
        actions.open { opens += 1 }
        actions.compose { presented = $0 }
        XCTAssertEqual(opens, 1)
        XCTAssertNotNil(presented)
        actions.drawFirstNode()
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertNil(EditorGetStartedActions(store: store, fileIdentity: file))
        store.cancelAddMode()
        actions.open { opens += 1 }
        XCTAssertEqual(opens, 1)
        XCTAssertNotNil(EditorGetStartedActions(store: store, fileIdentity: file))
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(store.canUndo)
    }

    func testEmptyCanvasDropStagesFrontAndSideAndRejectsRetainedSource() async throws {
        let store = makeStore()
        defer { store.stop() }
        let file = UUID()
        let blank = Dust3DDocument.emptyArchive()
        await store.load(data: blank, fileIdentity: file)
        var ownsWindow = true
        let actions = try XCTUnwrap(
            EditorGetStartedActions(store: store, fileIdentity: file, ownsWindow: { ownsWindow }))
        let front = URL(fileURLWithPath: "/tmp/front.png")
        let side = URL(fileURLWithPath: "/tmp/side.tiff")
        let ds3 = URL(fileURLWithPath: "/tmp/model.ds3")
        var writes = 0
        store.onDocumentChanged = { _ in writes += 1 }

        let staged = try XCTUnwrap(actions.referenceDrop([front, side]))
        XCTAssertEqual(staged.droppedSources?.front, front)
        XCTAssertEqual(staged.droppedSources?.side, side)
        XCTAssertNil(actions.referenceDrop([front, ds3]))
        XCTAssertNil(actions.referenceDrop([front, side, front]))
        XCTAssertEqual(store.snapshot?.document.encoded(), blank)
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(store.canUndo)

        ownsWindow = false
        XCTAssertNil(actions.referenceDrop([front]))
        ownsWindow = true
        let withNode = try Dust3DDocument(data: blank).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        await store.load(data: withNode.encoded(), fileIdentity: file)
        XCTAssertNil(actions.referenceDrop([front]))
        XCTAssertNil(EditorGetStartedActions(store: store, fileIdentity: file))
        await store.load(data: blank, fileIdentity: file)
        XCTAssertNil(actions.referenceDrop([front]))
        XCTAssertNotNil(EditorGetStartedActions(store: store, fileIdentity: file)?.referenceDrop([front]))
    }

    func testWorkingGroupChangeRejectsRetainedDrawWithoutWriting() async throws {
        let store = makeStore()
        defer { store.stop() }
        let file = UUID()
        let original = try Dust3DDocument(
            snapshotXML: Data("<canvas><components><component id='group'/></components></canvas>".utf8)
        ).encoded()
        await store.load(data: original, fileIdentity: file)
        let snapshot = try XCTUnwrap(store.snapshot)
        store.setCanvasContext(
            projection: CanvasProjection(bounds: store.bounds, plane: store.plane, width: 400, height: 300),
            width: 400, height: 300)
        let retained = try XCTUnwrap(EditorGetStartedActions(store: store, fileIdentity: file))
        XCTAssertTrue(retained.canDrawFirstNode)
        var writes = 0
        store.onDocumentChanged = { _ in writes += 1 }

        store.workingGroupAction(.group("group"), snapshot: snapshot)()
        XCTAssertEqual(store.addPlacementDestination, .group("group"))
        XCTAssertEqual(store.snapshot?.selectionRevision, snapshot.selectionRevision)
        XCTAssertEqual(store.snapshot?.documentRevision, snapshot.documentRevision)
        retained.drawFirstNode()
        XCTAssertFalse(store.isAddingNodes)

        let current = try XCTUnwrap(EditorGetStartedActions(store: store, fileIdentity: file))
        current.drawFirstNode()
        XCTAssertTrue(store.isAddingNodes)
        store.updateAddPointer(at: .init(x: 200, y: 150), modeID: store.addModeID)
        XCTAssertNotNil(store.addGhostPoint)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(store.canUndo)
    }

    func testOnlyAcceptedEmptySourceAdmitsTheCardAndRetainedActions() async throws {
        let store = makeStore()
        defer { store.stop() }
        let file = UUID()
        let blank = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        XCTAssertNil(EditorGetStartedActions(store: store, fileIdentity: file))
        await store.load(data: blank.encoded(), fileIdentity: file)
        XCTAssertNil(EditorGetStartedActions(store: store, fileIdentity: UUID()))
        let retained = try XCTUnwrap(EditorGetStartedActions(store: store, fileIdentity: file))
        await store.load(data: Data("invalid".utf8), fileIdentity: UUID())
        let loadError = try XCTUnwrap(store.errorMessage)
        XCTAssertNil(EditorGetStartedActions(store: store, fileIdentity: file))
        retained.open { XCTFail("A failed load must not open through a retained card") }
        retained.compose { _ in XCTFail("A failed load must not present a composer") }
        retained.drawFirstNode()
        XCTAssertFalse(store.isAddingNodes)
        XCTAssertEqual(store.errorMessage, loadError)

        let withPart = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts><part id='p'/></parts><components/></canvas>".utf8
            ))
        await store.load(data: withPart.encoded(), fileIdentity: file)
        XCTAssertNil(EditorGetStartedActions(store: store, fileIdentity: file))

        let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let withImage = try blank.applying(.setReferenceImagePNG(signature))
        await store.load(data: withImage.encoded(), fileIdentity: file)
        XCTAssertTrue(store.hasReferenceImage)
        XCTAssertNil(store.referenceImage)
        XCTAssertNil(EditorGetStartedActions(store: store, fileIdentity: file))

        await store.load(data: blank.encoded(), fileIdentity: file)
        XCTAssertNotNil(EditorGetStartedActions(store: store, fileIdentity: file))
        retained.open { XCTFail("A fresh blank source must not acquire old actions") }
    }
}
