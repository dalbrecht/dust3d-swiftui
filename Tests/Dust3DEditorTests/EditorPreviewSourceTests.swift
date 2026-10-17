import Dust3DDocument
import Dust3DKit
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorPreviewSourceTests: XCTestCase {
    func testSourceHintsFollowCurrentMeshAndAreUnavailableWhileStale() async throws {
        let document = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: document.encoded())
        try await settle(store)
        let hints = try XCTUnwrap(store.previewSourceHints)
        XCTAssertEqual(hints.corners.count, try XCTUnwrap(store.mesh).indices.count)
        XCTAssertNil(store.previewSourceIssue)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        store.retryPreview()
        XCTAssertTrue(store.previewState.isStale)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.previewSourceHints)
        try await settle(store)
        XCTAssertNotNil(store.previewSourceHints)
        XCTAssertGreaterThan(try XCTUnwrap(store.previewCacheStatistics).reusedComponentCount, 0)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(publications, 0)
        await store.load(data: Dust3DDocument.emptyArchive())
        XCTAssertNil(store.previewSourceHints)
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewSourceIssue)
        store.stop()
        XCTAssertNil(store.previewSourceHints)
    }

    func testSourcePayloadFailureRetainsOrdinaryMeshAndOriginalDiagnostic() async throws {
        let document = try StitchingFixture.document(loop: true, attributes: "", isolatedLoop: true)
        let service = EditorPreviewService(maximumSourcePayloadBytes: 1)
        let store = EditorStore(preview: service)
        defer { store.stop() }
        await store.load(data: document.encoded())
        try await settle(store)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.previewSourceHints)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertEqual(store.previewSourceIssue?.status, 4)
        XCTAssertTrue(store.previewSourceIssue?.message.contains("source") == true)
        XCTAssertTrue(store.canSave)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        store.stop()
        XCTAssertNil(store.previewSourceIssue)
    }

    func testSuccessfulEmptyAndSourceFallbackNeverRestoreOldMetadata() async throws {
        let data = try StitchingFixture.document(
            loop: true, attributes: "", fillLoopInterior: "false", isolatedLoop: true, includeUncombinedModel: false
        ).encoded()
        for budget in [0, 1] {
            let service = EditorPreviewService(maximumSourcePayloadBytes: budget)
            let result = try await service.generate(data, scopeID: UUID())
            XCTAssertNil(result.output)
            XCTAssertNil(result.mesh)
            XCTAssertEqual(result.statistics.outcome, .retained)
            XCTAssertEqual(result.sourceIssue?.status, budget == 0 ? nil : 4)
        }
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Preview did not settle")
    }
}
