import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor final class EditorErrorAnnouncementTests: XCTestCase {
    func testOnlyActiveDocumentErrorsWithoutAnExportAnnouncementAreSpoken() {
        let error = "The document could not be opened."
        XCTAssertEqual(EditorGeometryExportPhase.idle.editorErrorAnnouncement(error, isKeyWindow: true), error)
        XCTAssertNil(EditorGeometryExportPhase.idle.editorErrorAnnouncement(error, isKeyWindow: false))
        XCTAssertNil(EditorGeometryExportPhase.idle.editorErrorAnnouncement(nil, isKeyWindow: true))

        let exportError = CocoaError(.fileWriteNoPermission)
        let phase = EditorGeometryExportPhase.failed(exportError)
        let exportMessage = EditorStore.message(exportError)
        XCTAssertNil(phase.editorErrorAnnouncement(exportMessage, isKeyWindow: true))
        XCTAssertEqual(phase.editorErrorAnnouncement(error, isKeyWindow: true), error)
    }
}
