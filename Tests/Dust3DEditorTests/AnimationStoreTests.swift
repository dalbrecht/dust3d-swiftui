import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

private struct AnimationStoreNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

@MainActor
final class AnimationStoreTests: XCTestCase {
    private func document(name: String = "A") throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='\(name)' type='future' retained='keep'/><animation id='b' name='B' type='future'/></animations></canvas>"
                    .utf8))
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isLoadingAnimations { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Animation workflow did not settle")
    }
    private func refresh(_ store: EditorStore) async {
        store.refreshAnimations()
        await store.animationQuery?.value
    }

    func testListSelectionLatestRequestWinsWithoutPublishingOrRegeneratingDocument() async throws {
        let store = EditorStore(preview: AnimationStoreNoPreview())
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        XCTAssertNil(store.animationSnapshot)
        await refresh(store)
        XCTAssertEqual(store.animationSnapshot?.list.rows.count, 2)
        XCTAssertTrue(store.canManageAnimations)
        let revision = store.snapshot?.documentRevision
        let previewRevision = store.previewRevision
        var published = 0
        store.onDocumentChanged = { _ in published += 1 }
        store.selectAnimation("a")
        let first = store.animationQuery
        store.selectAnimation("b")
        let second = store.animationQuery
        await first?.value
        await second?.value
        XCTAssertEqual(store.animationSnapshot?.list.selectedRow?.source.id, "b")
        XCTAssertEqual(store.snapshot?.documentRevision, revision)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(store.previewRevision, previewRevision)
        XCTAssertEqual(published, 0)
    }

    func testMetadataMutationsUseExistingHistoryWithoutRegeneratingGeometry() async throws {
        let store = EditorStore(preview: AnimationStoreNoPreview())
        defer { store.stop() }
        await store.load(data: Dust3DDocument.emptyArchive())
        await refresh(store)
        let previewRevision = store.previewRevision
        store.createAnimation(name: "Walk", type: "future")
        try await settle(store)
        let current = try XCTUnwrap(store.animationSnapshot)
        let id = try XCTUnwrap(current.list.selectedRow?.source.id)
        var target = try AnimationEditTarget(snapshot: current, animationID: id)
        store.editAnimation(.rename("Renamed"), target: target)
        try await settle(store)
        XCTAssertEqual(store.animationSnapshot?.list.selectedRow?.title, "Renamed")
        target = try AnimationEditTarget(snapshot: XCTUnwrap(store.animationSnapshot), animationID: id)
        store.duplicateAnimation(target: target, name: "Copy")
        try await settle(store)
        let duplicated = try XCTUnwrap(store.animationSnapshot)
        XCTAssertEqual(duplicated.list.rows.count, 2)
        let copyID = try XCTUnwrap(duplicated.list.selectedRow?.source.id)
        target = try AnimationEditTarget(snapshot: duplicated, animationID: copyID)
        store.editAnimation(.delete, target: target)
        try await settle(store)
        XCTAssertEqual(store.animationSnapshot?.list.rows.count, 1)
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.previewRevision, previewRevision)
        store.undo()
        try await settle(store)
        XCTAssertNil(store.animationSnapshot, "Old metadata cannot masquerade as the current revision")
        await refresh(store)
        XCTAssertEqual(store.animationSnapshot?.list.rows.count, 2)
    }

    func testStaleDialogTargetsCannotEditAReplacementWithTheSameRecordIdentity() async throws {
        let store = EditorStore(preview: AnimationStoreNoPreview())
        defer { store.stop() }
        try await store.load(data: document().encoded())
        await refresh(store)
        let target = try AnimationEditTarget(snapshot: XCTUnwrap(store.animationSnapshot), animationID: "a")
        let replacement = try document(name: "Replacement")
        await store.load(data: replacement.encoded())
        await refresh(store)
        store.editAnimation(.rename("stale"), target: target)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), replacement.encoded())
        XCTAssertNotNil(store.errorMessage)
        store.stop()
        XCTAssertNil(store.animationSnapshot)
        XCTAssertFalse(store.canManageAnimations)
    }

    func testReloadAndStopRetirePendingQueriesAndIsolateOriginalSelectionErrors() async throws {
        let store = EditorStore(preview: AnimationStoreNoPreview())
        defer { store.stop() }
        try await store.load(data: document().encoded())
        await refresh(store)
        let identity = store.snapshot?.documentIdentity
        store.selectAnimation("missing")
        await store.animationQuery?.value
        XCTAssertEqual(store.animationQueryIssue as? DocumentAnimationError, .missingAnimation("missing"))
        XCTAssertTrue(store.canSave)
        store.setOrigin(x: "1", y: "2", z: "3")
        try await settle(store)
        XCTAssertNil(store.animationQueryIssue, "An old-source error must not label a new document revision")
        await refresh(store)
        XCTAssertNil(store.animationQueryIssue)
        XCTAssertTrue(store.canManageAnimations)
        store.selectAnimation("a")
        let old = store.animationQuery
        try await store.load(data: document(name: "Replacement").encoded())
        await old?.value
        XCTAssertNil(store.animationSnapshot)
        XCTAssertNil(store.animationQueryIssue)
        XCTAssertNotEqual(store.snapshot?.documentIdentity, identity)
        await refresh(store)
        XCTAssertEqual(store.animationSnapshot?.list.rows.first?.title, "Replacement")
        store.selectAnimation("b")
        let pending = store.animationQuery
        store.stop()
        await pending?.value
        XCTAssertNil(store.animationSnapshot)
        XCTAssertNil(store.animationQueryIssue)
        XCTAssertFalse(store.isLoadingAnimations)
    }

    func testOptionalCatalogFailureAndFailedOpenDoNotPromoteRetainedListState() async throws {
        let store = EditorStore(preview: AnimationStoreNoPreview())
        defer { store.stop() }
        let invalid = try Dust3DDocument(
            snapshotXML: Data("<canvas><animations><animation id='a'/><animation id='a'/></animations></canvas>".utf8))
        await store.load(data: invalid.encoded())
        await refresh(store)
        XCTAssertEqual(store.animationSnapshot?.list.issue as? DocumentAnimationError, .duplicateIdentity("a"))
        XCTAssertFalse(store.canManageAnimations)
        XCTAssertTrue(store.canSave)
        try await store.load(data: document().encoded())
        await refresh(store)
        XCTAssertNotNil(store.animationSnapshot)
        await store.load(data: Data())
        await refresh(store)
        XCTAssertNil(store.animationSnapshot)
        XCTAssertFalse(store.canManageAnimations)
    }
}
