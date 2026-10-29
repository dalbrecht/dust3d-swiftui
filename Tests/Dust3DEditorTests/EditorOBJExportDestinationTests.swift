import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorOBJExportDestinationTests: XCTestCase {
    func testShouldRejectMissingWindowWithoutGlobalFallback() async throws {
        let service = EditorOBJExportDestinationService()
        service.cancel()
        do {
            _ = try await service.chooseDestination(suggestedName: "Example.obj")
            XCTFail("A document window is required")
        } catch { XCTAssertEqual(error as? EditorOBJExportDestinationError, .unavailableWindow) }
    }

    func testShouldRejectDuplicateAndUnrelatedSheetsBeforePresentation() throws {
        XCTAssertThrowsError(
            try EditorOBJExportDestinationService.validateAvailability(isChoosing: true, hasAttachedSheet: true)
        ) {
            XCTAssertEqual($0 as? EditorOBJExportDestinationError, .alreadyChoosing)
        }
        XCTAssertThrowsError(
            try EditorOBJExportDestinationService.validateAvailability(isChoosing: false, hasAttachedSheet: true)
        ) {
            XCTAssertEqual($0 as? EditorOBJExportDestinationError, .anotherSheetActive)
        }
        XCTAssertNoThrow(
            try EditorOBJExportDestinationService.validateAvailability(isChoosing: false, hasAttachedSheet: false))
    }

    func testShouldValidateAcceptedDestinationAndIgnoreCancelledResponse() throws {
        let valid = URL(fileURLWithPath: "/owned/Example.OBJ")
        XCTAssertEqual(try EditorOBJExportDestinationService.destination(wasAccepted: true, url: valid), valid)
        XCTAssertNil(try EditorOBJExportDestinationService.destination(wasAccepted: false, url: valid))
        XCTAssertNil(try EditorOBJExportDestinationService.destination(wasAccepted: false, url: nil))
        XCTAssertThrowsError(try EditorOBJExportDestinationService.destination(wasAccepted: true, url: nil)) {
            XCTAssertEqual($0 as? EditorOBJExportDestinationError, .missingDestination)
        }
        for invalid in [
            URL(fileURLWithPath: "/owned/Example.txt"), try XCTUnwrap(URL(string: "https://example.test/file.obj")),
        ] {
            XCTAssertThrowsError(try EditorOBJExportDestinationService.destination(wasAccepted: true, url: invalid)) {
                XCTAssertEqual($0 as? DocumentExportError, .invalidDestination)
            }
        }
    }
}
