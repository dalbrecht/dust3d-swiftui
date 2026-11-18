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
}
