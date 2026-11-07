import XCTest

@testable import Dust3DEditor

final class CanvasProfilePaneLayoutTests: XCTestCase {
    func testOddAvailableWidthDividesEquallyWithoutDroppingFractionalPoint() {
        let width = CanvasProfileWorkspace.paneWidth(totalWidth: 302, dividerWidth: 1)
        XCTAssertEqual(width, 150.5)
        XCTAssertEqual(width * 2 + 1, 302)
    }

    func testDividerAtLeastAsWideAsAvailableSpaceProducesZero() {
        XCTAssertEqual(CanvasProfileWorkspace.paneWidth(totalWidth: 1, dividerWidth: 1), 0)
        XCTAssertEqual(CanvasProfileWorkspace.paneWidth(totalWidth: 1, dividerWidth: 2), 0)
    }

    func testNegativeOrNonfiniteDimensionsProduceZero() {
        for invalid in [-1.0, .infinity, -.infinity, .nan] {
            XCTAssertEqual(CanvasProfileWorkspace.paneWidth(totalWidth: invalid, dividerWidth: 1), 0)
            XCTAssertEqual(CanvasProfileWorkspace.paneWidth(totalWidth: 300, dividerWidth: invalid), 0)
        }
    }
}
