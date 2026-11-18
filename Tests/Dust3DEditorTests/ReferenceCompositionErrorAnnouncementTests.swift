import XCTest

@testable import Dust3DEditor

@MainActor final class ReferenceCompositionErrorAnnouncementTests: XCTestCase {
    func testOnlyNewErrorsInTheActiveSheetAreAnnounced() {
        let anchor = ReferenceCompositionErrorAnnouncementAnchor()
        var messages: [String] = []
        let announce: (String) -> Void = { messages.append($0) }
        anchor.update(message: "Invalid crop", isActive: false, announce: announce)
        anchor.update(message: "Invalid crop", isActive: true, announce: announce)
        XCTAssertTrue(messages.isEmpty)

        anchor.update(message: "Apply failed", isActive: true, announce: announce)
        anchor.update(message: "Apply failed", isActive: true, announce: announce)
        anchor.update(message: "", isActive: true, announce: announce)
        anchor.update(message: nil, isActive: true, announce: announce)
        anchor.update(message: "Apply failed", isActive: true, announce: announce)
        XCTAssertEqual(messages, ["Apply failed", "Apply failed"])
    }
}
