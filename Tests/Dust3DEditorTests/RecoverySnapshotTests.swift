import Dust3DDocument
import XCTest

@testable import Dust3DEditor

final class RecoverySnapshotTests: XCTestCase {
    @MainActor func testCapturePreservesAcceptedBytesHistoryAndRejectsUnavailableState() async throws {
        let store = EditorStore()
        let id = UUID()
        XCTAssertThrowsError(try store.recoverySnapshot(documentID: id)) {
            XCTAssertEqual($0 as? EditorRecoveryCopyError, .notLoaded)
        }
        let bytes = Dust3DDocument.emptyArchive()
        await store.load(data: bytes)
        let before = try XCTUnwrap(store.snapshot)
        let captured = try store.recoverySnapshot(documentID: id)
        XCTAssertEqual(captured.request.documentID, id)
        XCTAssertEqual(captured.document.encoded(), before.document.encoded())
        XCTAssertEqual(captured.request.revision, before.documentRevision)
        XCTAssertEqual(store.snapshot?.documentRevision, before.documentRevision)
        XCTAssertEqual(store.snapshot?.canUndo, before.canUndo)
        store.addNode()
        XCTAssertThrowsError(try store.recoverySnapshot(documentID: id)) {
            XCTAssertEqual($0 as? EditorRecoveryCopyError, .editInProgress)
        }
        store.stop()
        XCTAssertThrowsError(try store.recoverySnapshot(documentID: id)) {
            XCTAssertEqual($0 as? EditorRecoveryCopyError, .stopped)
        }
    }
}
