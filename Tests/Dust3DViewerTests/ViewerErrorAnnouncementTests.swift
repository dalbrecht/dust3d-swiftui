import XCTest

@testable import Dust3DViewer

@MainActor
final class ViewerErrorAnnouncementTests: XCTestCase {
    func testOnlyNewVisibleErrorsSpeakWhileTheirViewerWindowIsActive() {
        let anchor = ViewerErrorAnnouncementAnchor()
        var spoken: [String] = []
        let announce: (String) -> Void = { spoken.append($0) }

        anchor.update(message: "Inactive error", isActive: false, announce: announce)
        anchor.update(message: "Inactive error", isActive: true, announce: announce)
        anchor.update(message: "", isActive: true, announce: announce)
        XCTAssertTrue(spoken.isEmpty)

        anchor.update(message: "Cannot open document", isActive: true, announce: announce)
        anchor.update(message: "Cannot open document", isActive: true, announce: announce)
        XCTAssertEqual(spoken, ["Cannot open document"])

        anchor.update(message: nil, isActive: true, announce: announce)
        anchor.update(message: "Cannot open document", isActive: true, announce: announce)
        XCTAssertEqual(spoken, ["Cannot open document", "Cannot open document"])
    }

    func testMaterialFallbackSpeaksOnceAndYieldsToANewViewerError() {
        let anchor = ViewerErrorAnnouncementAnchor()
        var spoken: [String] = []
        let announce: (String) -> Void = { spoken.append($0) }

        anchor.update(message: nil, materialIssue: "Texture failed", isActive: false, announce: announce)
        anchor.update(message: nil, materialIssue: "Texture failed", isActive: true, announce: announce)
        XCTAssertTrue(spoken.isEmpty)

        anchor.update(message: nil, materialIssue: "Invalid image", isActive: true, announce: announce)
        anchor.update(message: nil, materialIssue: "Invalid image", isActive: true, announce: announce)
        XCTAssertEqual(spoken, ["Showing geometry without materials. Invalid image"])

        anchor.update(
            message: "Cannot open document", materialIssue: "Decode failed", isActive: true, announce: announce)
        anchor.update(message: nil, materialIssue: "Decode failed", isActive: true, announce: announce)
        XCTAssertEqual(spoken, ["Showing geometry without materials. Invalid image", "Cannot open document"])

        anchor.update(message: nil, materialIssue: nil, isActive: true, announce: announce)
        anchor.update(message: nil, materialIssue: "Decode failed", isActive: true, announce: announce)
        XCTAssertEqual(spoken.last, "Showing geometry without materials. Decode failed")
    }
}
