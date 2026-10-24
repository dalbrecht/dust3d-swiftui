import Dust3DDocument
import XCTest

@testable import Dust3DEditorModel

final class EditorExportTargetTests: XCTestCase {
    func testPublicationPropagatesOriginalWriteCauseWithoutEditingHistory() async throws {
        enum PublicationCause: Error, Equatable { case unavailable }
        let session = EditorSession()
        let snapshot = try await session.open(data: Dust3DDocument.emptyArchive())
        let target = EditorExportTarget(snapshot: snapshot)
        do {
            try await session.publishExport(target, publication: { throw PublicationCause.unavailable })
            XCTFail("Original publication cause must propagate")
        } catch { XCTAssertEqual(error as? PublicationCause, .unavailable) }
        try await session.validateExport(target)
        let unchanged = try await session.apply([])
        XCTAssertEqual(unchanged.document.encoded(), snapshot.document.encoded())
        XCTAssertEqual(unchanged.documentRevision, snapshot.documentRevision)
        XCTAssertFalse(unchanged.canUndo)
    }

    func testUnloadedAndOtherWindowRejectWithoutChangingCurrentDocument() async throws {
        let first = EditorSession()
        let snapshot = try await first.open(data: Dust3DDocument.emptyArchive())
        let target = EditorExportTarget(snapshot: snapshot)
        let second = EditorSession()
        do {
            try await second.validateExport(target)
            XCTFail("An unloaded session cannot admit an export")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        let other = try await second.open(data: snapshot.document.encoded())
        XCTAssertEqual(other.documentRevision, snapshot.documentRevision)
        do {
            try await second.validateExport(target)
            XCTFail("Matching revision numbers from separate windows are not interchangeable")
        } catch { XCTAssertEqual(error as? EditorError, .staleExport) }
        try await first.validateExport(target)
        let unchanged = try await second.apply([])
        XCTAssertEqual(unchanged.document.encoded(), other.document.encoded())
        XCTAssertEqual(unchanged.documentRevision, other.documentRevision)
        XCTAssertFalse(unchanged.canUndo)
    }
}
