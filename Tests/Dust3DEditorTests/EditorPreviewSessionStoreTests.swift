import Dust3DDocument
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorPreviewSessionStoreTests: XCTestCase {
    func testCacheIssueDoesNotBecomeAGenerationOrDocumentFailure() async throws {
        let original = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true)
        let store = EditorStore(preview: EditorPreviewService(maximumCachePayloadBytes: 1))
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.previewCacheStatistics?.cacheIssue?.status, 4)
        XCTAssertTrue(store.canSave)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.stop()
        XCTAssertNil(store.previewCacheStatistics)
        XCTAssertNil(store.mesh)
    }

    func testLateOldResultCannotReplaceNewDocumentCacheDiagnostics() async throws {
        let original = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true)
        let bytes = original.encoded()
        let replacement = try StitchingFixture.document(
            loop: true, attributes: "", isolatedLoop: true, includeUncombinedModel: false
        ).encoded()
        let normal = EditorPreviewResult(
            sourced: try await MeshGenerationSession().generateSourcedIndexed(data: replacement))
        let degraded = EditorPreviewResult(
            sourced: try await MeshGenerationSession(maximumCachePayloadBytes: 1).generateSourcedIndexed(data: bytes))
        let preview = SuspendedPreviewService()
        let store = EditorStore(preview: preview)
        defer {
            store.stop()
            Task { await preview.finishAll(normal) }
        }
        await store.load(data: bytes)
        try await waitForRequests(1, preview)
        let previousRequest = try XCTUnwrap(store.generation)
        await store.load(data: replacement)
        try await waitForRequests(2, preview)
        let scopes = await preview.scopes
        XCTAssertNotEqual(scopes[0], scopes[1])
        await preview.finish(1, normal)
        try await settle(store)
        let revision = store.previewRevision
        XCTAssertNil(store.previewCacheStatistics?.cacheIssue)
        await preview.finish(0, degraded)
        await previousRequest.value
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertNil(store.previewCacheStatistics?.cacheIssue)
        XCTAssertNotNil(store.mesh)
        XCTAssertEqual(store.previewSourceHints, normal.output?.sourceHints)
        XCTAssertEqual(store.previewSourceHints?.identities.count, 4)
        XCTAssertEqual(store.mesh?.nodeCount, 4)
        XCTAssertEqual(store.snapshot?.document.encoded(), replacement)
    }

    func testLateResultAfterStopCannotRestoreMeshOrStatistics() async throws {
        let bytes = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true).encoded()
        let normal = EditorPreviewResult(sourced: try await MeshGenerationSession().generateSourcedIndexed(data: bytes))
        let preview = SuspendedPreviewService()
        let store = EditorStore(preview: preview)
        defer {
            store.stop()
            Task { await preview.finishAll(normal) }
        }
        await store.load(data: bytes)
        try await waitForRequests(1, preview)
        let previousRequest = try XCTUnwrap(store.generation)
        store.stop()
        await preview.finish(0, normal)
        await previousRequest.value
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewSourceHints)
        XCTAssertNil(store.previewSourceIssue)
        XCTAssertNil(store.previewCacheStatistics)
        XCTAssertFalse(store.canSave)
    }

    func testRetryReusesCacheWhileReplacementAndEmptyDocumentsStartFresh() async throws {
        let original = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertEqual(store.previewCacheStatistics?.reusedComponentCount, 0)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        store.retryPreview()
        try await settle(store)
        XCTAssertGreaterThan(try XCTUnwrap(store.previewCacheStatistics).reusedComponentCount, 0)
        await store.load(data: Dust3DDocument.emptyArchive())
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewCacheStatistics)
        XCTAssertFalse(store.isGenerating)
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertEqual(store.previewCacheStatistics?.reusedComponentCount, 0)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(publications, 0)
    }

    func testGenerationFailureKeepsLastMeshAndRetrySeparatesCacheIssue() async throws {
        let bytes = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true).encoded()
        let normal = EditorPreviewResult(sourced: try await MeshGenerationSession().generateSourcedIndexed(data: bytes))
        let degraded = EditorPreviewResult(
            sourced: try await MeshGenerationSession(maximumCachePayloadBytes: 1).generateSourcedIndexed(data: bytes))
        let preview = SuspendedPreviewService()
        let store = EditorStore(preview: preview)
        defer {
            store.stop()
            Task { await preview.finishAll(normal) }
        }
        await store.load(data: bytes)
        try await waitForRequests(1, preview)
        await preview.finish(0, normal)
        try await settle(store)
        let positions = try XCTUnwrap(store.mesh).vertices.map(\.position)
        store.retryPreview()
        try await waitForRequests(2, preview)
        await preview.fail(1)
        try await settle(store)
        XCTAssertEqual(store.mesh?.vertices.map(\.position), positions)
        XCTAssertTrue(store.previewState.isStale)
        XCTAssertNil(store.previewSourceHints)
        XCTAssertEqual(store.previewState.errorMessage, "Original preview generation cause")
        XCTAssertNil(store.previewCacheStatistics)
        XCTAssertTrue(store.canSave)
        store.retryPreview()
        try await waitForRequests(3, preview)
        await preview.finish(2, degraded)
        try await settle(store)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertFalse(store.previewState.isStale)
        XCTAssertNotNil(store.previewSourceHints)
        XCTAssertEqual(store.previewCacheStatistics?.cacheIssue?.status, 4)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Preview did not settle")
    }

    private func waitForRequests(_ count: Int, _ preview: SuspendedPreviewService) async throws {
        for _ in 0..<300 {
            if await preview.scopes.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected preview request did not arrive")
    }
}

private actor SuspendedPreviewService: EditorPreviewServing {
    private struct Pending {
        let scope: UUID
        var continuation: CheckedContinuation<EditorPreviewResult, any Error>?
    }
    private var pending: [Pending] = []
    var scopes: [UUID] { pending.map(\.scope) }

    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(Pending(scope: scopeID, continuation: continuation))
        }
    }
    func reset(scopeID: UUID) async throws {}
    func finish(_ index: Int, _ result: EditorPreviewResult) {
        pending[index].continuation?.resume(returning: result)
        pending[index].continuation = nil
    }
    private enum Failure: LocalizedError {
        case generation
        var errorDescription: String? { "Original preview generation cause" }
    }
    func fail(_ index: Int) {
        pending[index].continuation?.resume(throwing: Failure.generation)
        pending[index].continuation = nil
    }
    func finishAll(_ result: EditorPreviewResult) {
        for index in pending.indices { finish(index, result) }
    }
}
