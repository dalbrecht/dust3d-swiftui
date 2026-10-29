import Dust3DKit
import Foundation
import UniformTypeIdentifiers
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorGeometryExportDestinationTests: XCTestCase {
    func testSelectedFormatsProvideNativePanelTypes() throws {
        for format in [DocumentExportFormat.obj, .fbx] {
            let type = try EditorGeometryExportDestinationService.contentType(for: format)
            XCTAssertEqual(type.preferredFilenameExtension, format.rawValue)
        }
    }

    func testFBXDestinationRejectsOBJAndKeepsCaseInsensitiveFBXExtension() throws {
        let valid = URL(fileURLWithPath: "/owned/Example.FBX")
        XCTAssertEqual(
            try EditorGeometryExportDestinationService.destination(
                wasAccepted: true, url: valid, format: .fbx), valid)
        XCTAssertThrowsError(
            try EditorGeometryExportDestinationService.destination(
                wasAccepted: true, url: URL(fileURLWithPath: "/owned/Example.obj"), format: .fbx))
    }

    func testShouldRejectMissingWindowWithoutGlobalFallback() async throws {
        let service = EditorGeometryExportDestinationService()
        service.cancel()
        do {
            _ = try await service.chooseDestination(suggestedName: "Example.obj")
            XCTFail("A document window is required")
        } catch { XCTAssertEqual(error as? EditorGeometryExportDestinationError, .unavailableWindow) }
    }

    func testShouldRejectDuplicateAndUnrelatedSheetsBeforePresentation() throws {
        XCTAssertThrowsError(
            try EditorGeometryExportDestinationService.validateAvailability(isChoosing: true, hasAttachedSheet: true)
        ) {
            XCTAssertEqual($0 as? EditorGeometryExportDestinationError, .alreadyChoosing)
        }
        XCTAssertThrowsError(
            try EditorGeometryExportDestinationService.validateAvailability(isChoosing: false, hasAttachedSheet: true)
        ) {
            XCTAssertEqual($0 as? EditorGeometryExportDestinationError, .anotherSheetActive)
        }
        XCTAssertNoThrow(
            try EditorGeometryExportDestinationService.validateAvailability(isChoosing: false, hasAttachedSheet: false))
    }

    func testShouldValidateAcceptedDestinationAndIgnoreCancelledResponse() throws {
        let valid = URL(fileURLWithPath: "/owned/Example.OBJ")
        XCTAssertEqual(try EditorGeometryExportDestinationService.destination(wasAccepted: true, url: valid), valid)
        XCTAssertNil(try EditorGeometryExportDestinationService.destination(wasAccepted: false, url: valid))
        XCTAssertNil(try EditorGeometryExportDestinationService.destination(wasAccepted: false, url: nil))
        XCTAssertThrowsError(try EditorGeometryExportDestinationService.destination(wasAccepted: true, url: nil)) {
            XCTAssertEqual($0 as? EditorGeometryExportDestinationError, .missingDestination)
        }
        for invalid in [
            URL(fileURLWithPath: "/owned/Example.txt"), try XCTUnwrap(URL(string: "https://example.test/file.obj")),
        ] {
            XCTAssertThrowsError(
                try EditorGeometryExportDestinationService.destination(wasAccepted: true, url: invalid)
            ) {
                XCTAssertEqual($0 as? DocumentExportError, .invalidDestination)
            }
        }
    }
}
