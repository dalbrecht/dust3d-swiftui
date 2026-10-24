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
    @MainActor func testFailedReplacementLoadCannotRelabelPreviousDocumentAsRecoveryCopy() async throws {
        let store = EditorStore()
        let original = Dust3DDocument.emptyArchive()
        await store.load(data: original)
        await store.generation?.value
        let accepted = try XCTUnwrap(store.snapshot)
        await store.load(data: Data("not an archive".utf8))
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.documentIdentity, accepted.documentIdentity)
        XCTAssertEqual(store.snapshot?.document.encoded(), accepted.document.encoded())
        XCTAssertThrowsError(try store.recoverySnapshot(documentID: UUID())) {
            XCTAssertEqual($0 as? DocumentError, .invalidArchive)
        }
        await store.load(data: original)
        XCTAssertEqual(try store.recoverySnapshot(documentID: UUID()).document.encoded(), original)
        let generation = store.generation
        store.stop()
        await generation?.value
    }

    @MainActor func testCaptureRequiresAcceptedFileIdentityBeforeReplacementStarts() async throws {
        let store = EditorStore()
        let first = UUID()
        let replacement = UUID()
        let bytes = Dust3DDocument.emptyArchive()
        await store.load(data: bytes, fileIdentity: first)
        XCTAssertEqual(try store.recoverySnapshot(documentID: first).document.encoded(), bytes)
        XCTAssertThrowsError(try store.recoverySnapshot(documentID: replacement)) {
            XCTAssertEqual($0 as? EditorRecoveryCopyError, .identityMismatch)
        }
        await store.load(data: bytes, fileIdentity: replacement)
        XCTAssertEqual(try store.recoverySnapshot(documentID: replacement).document.encoded(), bytes)
        XCTAssertThrowsError(try store.recoverySnapshot(documentID: first)) {
            XCTAssertEqual($0 as? EditorRecoveryCopyError, .identityMismatch)
        }
        let generation = store.generation
        store.stop()
        await generation?.value
    }

}
