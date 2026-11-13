import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor final class EditorSessionDiagnosticsTests: XCTestCase {
    func testSessionLogKeepsOnlyRecentEventsInOrderAndExportsTheVisibleSnapshot() {
        let log = EditorSessionDiagnostics()
        let start = Date(timeIntervalSince1970: 0)
        for offset in 0..<256 {
            log.record(.documentOpened, at: start.addingTimeInterval(Double(offset)))
        }
        log.record(.documentOpenFailed, at: start.addingTimeInterval(256))

        XCTAssertEqual(log.entries.count, 256)
        XCTAssertEqual(log.entries.first?.date, start.addingTimeInterval(1))
        XCTAssertEqual(log.entries.last?.event, .documentOpenFailed)
        let snapshot = log.exportText
        let lines = snapshot.split(separator: "\n")
        XCTAssertEqual(lines.count, 256)
        XCTAssertEqual(lines.first, "1970-01-01T00:00:01Z  Document opened")
        XCTAssertEqual(lines.last, "1970-01-01T00:04:16Z  Document could not be opened")

        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertTrue(log.exportText.isEmpty)
        log.record(.exportCompleted, at: start.addingTimeInterval(257))
        XCTAssertEqual(log.exportText, "1970-01-01T00:04:17Z  Geometry export completed\n")
        XCTAssertEqual(snapshot.split(separator: "\n").count, 256)
    }

    func testDocumentReadingRecordsRejectedFilesWithoutChangingTheError() throws {
        let log = EditorSessionDiagnostics()
        let recordFailure = { log.record(.documentOpenFailed) }
        let invalidData = Data("private input must stay out of diagnostics".utf8)
        let invalidFile = FileWrapper(regularFileWithContents: invalidData)

        var expected: (any Error)?
        XCTAssertThrowsError(try EditorFileDocument(data: invalidData)) { expected = $0 }
        XCTAssertThrowsError(try EditorFileDocument(reading: invalidFile, onFailure: recordFailure)) { actual in
            XCTAssertEqual(actual as NSError, expected.map { $0 as NSError })
        }
        XCTAssertThrowsError(
            try EditorFileDocument(reading: FileWrapper(directoryWithFileWrappers: [:]), onFailure: recordFailure)
        ) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile)
        }
        let validFile = FileWrapper(regularFileWithContents: Dust3DDocument.emptyArchive())
        _ = try EditorFileDocument(reading: validFile, onFailure: recordFailure)

        XCTAssertEqual(log.entries.map(\.event), [.documentOpenFailed, .documentOpenFailed])
        XCTAssertFalse(log.exportText.contains("private input"))
    }

    func testEditorLoadsRecordOutcomesWithoutCopyingInvalidInputIntoTheLog() async {
        let log = EditorSessionDiagnostics()
        let store = EditorStore(diagnostics: log)
        defer { store.stop() }

        await store.load(data: Dust3DDocument.emptyArchive())
        await store.load(data: Data("private input must stay out of diagnostics".utf8))

        XCTAssertEqual(log.entries.map(\.event), [.documentOpened, .documentOpenFailed])
        XCTAssertFalse(log.exportText.contains("private input"))
    }
}
