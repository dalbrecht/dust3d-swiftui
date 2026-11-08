import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct OriginDraftNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
final class OriginInspectorDraftTests: XCTestCase {
    private func makeStore() -> EditorStore {
        let stub = OriginDraftNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
    }

    private func archive(_ marker: String) throws -> Data {
        try Dust3DDocument(
            snapshotXML: Data("<canvas originX='1' originY='2' originZ='3' marker='\(marker)'/>".utf8)
        ).encoded()
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Origin operation did not settle")
    }

    func testSameOriginReplacementRetiresDraftResetAndApply() async throws {
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: try archive("first"), fileIdentity: UUID())
        let first = try XCTUnwrap(store.originInspectorSource)
        var draft = OriginInspectorDraft()
        draft.synchronize(to: first)
        draft.x = "9"
        let applyFirst = try XCTUnwrap(store.originInspectorApplyAction(source: first))

        let secondArchive = try archive("second")
        await store.load(data: secondArchive, fileIdentity: UUID())
        let second = try XCTUnwrap(store.originInspectorSource)
        XCTAssertNotEqual(first, second)
        draft.synchronize(to: second)
        XCTAssertEqual(draft.x, "1.0")
        draft.x = "6"
        draft.reset(for: first)
        XCTAssertEqual(draft.x, "6")

        applyFirst("invalid", "2", "3")
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.document.encoded(), secondArchive)
        XCTAssertFalse(store.canUndo)

        let applySecond = try XCTUnwrap(store.originInspectorApplyAction(source: second))
        applySecond(draft.x, draft.y, draft.z)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin, .init(x: 6, y: 2, z: 3))
        XCTAssertTrue(store.canUndo)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), secondArchive)
        XCTAssertFalse(store.canUndo)
    }

    func testUnrelatedDocumentRevisionPreservesDraftButFailedLoadRetiresIt() async throws {
        let store = makeStore()
        defer { store.stop() }
        let original = try archive("original")
        await store.load(data: original)
        let source = try XCTUnwrap(store.originInspectorSource)
        var draft = OriginInspectorDraft()
        draft.synchronize(to: source)
        draft.y = "8"
        let revision = try XCTUnwrap(store.snapshot?.documentRevision)
        store.setRigType(.fish)
        try await settle(store)
        let changed = try XCTUnwrap(store.snapshot)
        XCTAssertGreaterThan(changed.documentRevision, revision)
        XCTAssertEqual(store.originInspectorSource, source)
        draft.synchronize(to: store.originInspectorSource)
        XCTAssertEqual(draft.y, "8")
        let apply = try XCTUnwrap(store.originInspectorApplyAction(source: source))
        await store.load(data: Data("invalid DS3".utf8))
        let diagnostic = try XCTUnwrap(store.errorMessage)
        XCTAssertNil(store.originInspectorSource)
        draft.synchronize(to: store.originInspectorSource)
        XCTAssertEqual(draft.y, "")
        apply("7", "8", "9")
        XCTAssertEqual(store.errorMessage, diagnostic)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed.document.encoded())
        XCTAssertFalse(store.canUndo)
    }
}
