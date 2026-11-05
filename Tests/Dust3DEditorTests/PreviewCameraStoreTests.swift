import Dust3DDocument
import XCTest

@testable import Dust3DEditor

@MainActor final class PreviewCameraStoreTests: XCTestCase {
    func testCameraCommandsAreWindowLocalPresentationAndFitDoesNotChangeTheArchiveOrHistory() async throws {
        let store = EditorStore()
        let other = EditorStore()
        defer {
            store.stop()
            other.stop()
        }
        store.movePreviewCamera(.panRight)
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertFalse(store.canMovePreviewCamera)
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                radius: 0.1))
        await store.load(data: source.encoded())
        try await settle(store)
        XCTAssertTrue(store.canMovePreviewCamera)
        let revision = store.previewRevision
        let reset = store.cameraReset
        store.movePreviewCamera(.panRight)
        XCTAssertNotNil(store.previewCameraCommand)
        XCTAssertNil(other.previewCameraCommand)
        XCTAssertEqual(store.cameraReset, reset)
        store.fitPreviewCamera()
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertEqual(store.cameraReset, reset + 1)
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        store.movePreviewCamera(.orbitLeft)
        store.renderError = "Renderer unavailable"
        XCTAssertFalse(store.canMovePreviewCamera)
        XCTAssertNil(store.previewCameraCommand)
        let failedReset = store.cameraReset
        store.movePreviewCamera(.zoomIn)
        store.fitPreviewCamera()
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertEqual(store.cameraReset, failedReset)
        store.renderError = nil
        XCTAssertTrue(store.canMovePreviewCamera)
        store.movePreviewCamera(.orbitLeft)
        store.selectAllNodes()
        try await settle(store)
        store.deleteSelection()
        try await settle(store)
        XCTAssertFalse(store.canMovePreviewCamera)
        XCTAssertNil(store.previewCameraCommand)
        await store.load(data: source.encoded())
        try await settle(store)
        XCTAssertNil(store.previewCameraCommand)
        store.movePreviewCamera(.orbitRight)
        store.fit()
        XCTAssertNil(store.previewCameraCommand)
        store.movePreviewCamera(.zoomIn)
        store.stop()
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertFalse(store.canMovePreviewCamera)
        let stoppedReset = store.cameraReset
        store.movePreviewCamera(.zoomOut)
        store.fitPreviewCamera()
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertEqual(store.cameraReset, stoppedReset)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Preview camera source did not settle")
    }
}
