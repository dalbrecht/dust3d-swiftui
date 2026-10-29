import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct AuthoringStoreNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}
private enum AuthoringStoreCause: Error, Equatable { case definitions }
private struct AuthoringStoreFailedCatalog: AnimationCatalogLoading {
    func load() async throws -> AnimationAuthoringCatalog { throw AuthoringStoreCause.definitions }
}

@MainActor
final class AnimationAuthoringStoreTests: XCTestCase {
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isLoadingAnimations { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Authoring transaction did not settle")
    }
    private func refresh(_ store: EditorStore) async {
        store.refreshAnimations()
        await store.animationQuery?.value
    }

    func testOptionalDefinitionFailureCannotBlockSaveOrExistingAnimationEdits() async throws {
        let store = EditorStore(preview: AuthoringStoreNoPreview(), animationCatalog: AuthoringStoreFailedCatalog())
        defer { store.stop() }
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='A' type='future' opaque='keep'/></animations></canvas>"
                    .utf8))
        await store.load(data: source.encoded())
        await refresh(store)
        let previewRevision = store.previewRevision
        await store.authoringCatalog.load()?.value
        XCTAssertEqual(store.authoringCatalog.issue as? AuthoringStoreCause, .definitions)
        XCTAssertTrue(store.canSave)
        XCTAssertTrue(store.canManageAnimations)
        XCTAssertFalse(store.isWorking)
        XCTAssertNil(store.errorMessage)
        let target = try AnimationEditTarget(snapshot: XCTUnwrap(store.animationSnapshot), animationID: "a")
        store.editAnimation(.rename("Renamed"), target: target)
        try await settle(store)
        XCTAssertEqual(store.animationSnapshot?.list.selectedRow?.source.id, nil)
        XCTAssertEqual(store.animationSnapshot?.list.rows.first?.title, "Renamed")
        XCTAssertEqual(store.animationSnapshot?.list.rows.first?.source.parameter(named: "opaque"), "keep")
        XCTAssertEqual(store.previewRevision, previewRevision)
        XCTAssertTrue(store.canSave)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
    }

    func testCapturedCreationAndParameterBatchPublishOnceEachWithoutRegeneratingPreview() async throws {
        let store = EditorStore(preview: AuthoringStoreNoPreview())
        defer { store.stop() }
        await store.load(data: Dust3DDocument.emptyArchive())
        await refresh(store)
        let previewRevision = store.previewRevision
        let creation = try AnimationCreationTarget(snapshot: XCTUnwrap(store.animationSnapshot))
        var publications = 0
        var accepted = false
        store.onDocumentChanged = { _ in publications += 1 }
        store.createAnimation(
            name: "New", type: "Known",
            parameters: [DocumentAnimationParameter(name: "durationSeconds", value: "1.250")],
            target: creation, completion: { accepted = $0 })
        try await settle(store)
        XCTAssertTrue(accepted)
        XCTAssertEqual(publications, 1)
        let created = try XCTUnwrap(store.animationSnapshot)
        let id = try XCTUnwrap(created.list.selectedRow?.source.id)
        let target = try AnimationEditTarget(snapshot: created, animationID: id)
        store.editAnimation(
            [
                .setParameter(name: "durationSeconds", value: "2.50"), .setParameter(name: "frameCount", value: "60"),
            ], target: target, completion: { accepted = $0 })
        try await settle(store)
        XCTAssertTrue(accepted)
        XCTAssertEqual(publications, 2)
        let edited = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(store.previewRevision, previewRevision)
        let reopened = try Dust3DDocument(data: edited.document.encoded())
        XCTAssertEqual(try reopened.animations().first?.parameter(named: "durationSeconds"), "2.50")
        XCTAssertEqual(try reopened.animations().first?.parameter(named: "frameCount"), "60")
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), created.editor.document.encoded())
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), edited.document.encoded())
    }

    func testCapturedCreationCannotRetargetReplacementAndStopRetiresOptionalDefinitions() async throws {
        let store = EditorStore(preview: AuthoringStoreNoPreview(), animationCatalog: AuthoringStoreFailedCatalog())
        await store.load(data: Dust3DDocument.emptyArchive())
        await refresh(store)
        let target = try AnimationCreationTarget(snapshot: XCTUnwrap(store.animationSnapshot))
        await store.load(data: Dust3DDocument.emptyArchive(), fileIdentity: UUID())
        await refresh(store)
        let replacement = store.snapshot?.document.encoded()
        var accepted = true
        store.createAnimation(
            name: "stale", type: "Known", parameters: [], target: target, completion: { accepted = $0 })
        try await settle(store)
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.snapshot?.document.encoded(), replacement)
        XCTAssertTrue(store.animationSnapshot?.list.rows.isEmpty == true)
        XCTAssertEqual(store.errorMessage, "The document changed. Select the animation again before editing.")
        store.stop()
        XCTAssertFalse(store.authoringCatalog.canLoad)
        XCTAssertNil(store.authoringCatalog.load())
    }
}
