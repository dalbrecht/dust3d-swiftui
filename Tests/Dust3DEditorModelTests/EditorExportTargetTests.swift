import Dust3DDocument
import XCTest

@testable import Dust3DEditorModel

final class EditorExportTargetTests: XCTestCase {
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
