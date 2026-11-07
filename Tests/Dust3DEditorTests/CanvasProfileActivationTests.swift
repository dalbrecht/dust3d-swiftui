import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class CanvasProfileActivationTests: XCTestCase {
    private let start = CanvasPoint(x: 20, y: 20)

    func testPlainPrimaryClickActivatesOnlyOnceOnInsideRelease() {
        var press = CanvasProfileActivationPress()
        press.begin(at: start, clickCount: 1, isPlainPrimary: true)
        press.move(to: .init(x: 21, y: 20))
        XCTAssertTrue(press.finish(at: .init(x: 21, y: 20), isInside: true))
        XCTAssertFalse(press.finish(at: start, isInside: true))
    }

    func testDragDoesNotActivateAfterReturningToPressPoint() {
        var press = CanvasProfileActivationPress()
        press.begin(at: start, clickCount: 1, isPlainPrimary: true)
        press.move(to: .init(x: 30, y: 20))
        press.move(to: start)
        XCTAssertFalse(press.finish(at: start, isInside: true))

        press.begin(at: start, clickCount: 1, isPlainPrimary: true)
        XCTAssertFalse(press.finish(at: .init(x: 30, y: 20), isInside: true))
    }

    func testOutsideReleaseCancellationAndNonplainOrRepeatedPressDoNotActivate() {
        var press = CanvasProfileActivationPress()
        press.begin(at: start, clickCount: 1, isPlainPrimary: true)
        XCTAssertFalse(press.finish(at: start, isInside: false))
        press.begin(at: start, clickCount: 1, isPlainPrimary: true)
        press.cancel()
        XCTAssertFalse(press.finish(at: start, isInside: true))
        press.begin(at: start, clickCount: 1, isPlainPrimary: false)
        XCTAssertFalse(press.finish(at: start, isInside: true))
        press.begin(at: start, clickCount: 2, isPlainPrimary: true)
        XCTAssertFalse(press.finish(at: start, isInside: true))
    }

    func testFollowThroughIsSuppressedUntilAFreshPressOnTheSameLease() {
        var workspace = CanvasProfileWorkspace()
        workspace.setDualProfile(true)
        workspace.activate(.side)
        let lease = workspace.lease
        workspace.markActivationClick()
        XCTAssertFalse(workspace.admitsPrimaryPress(clickCount: 2, lease: lease))
        XCTAssertFalse(workspace.admitsPrimaryPress(clickCount: 3, lease: lease))
        XCTAssertTrue(workspace.admitsPrimaryPress(clickCount: 1, lease: lease))
        XCTAssertTrue(workspace.admitsPrimaryPress(clickCount: 2, lease: lease))
    }

    func testPlaneAndLayoutChangesResetSuppressionWithoutRevivingOldLease() {
        var workspace = CanvasProfileWorkspace()
        workspace.setDualProfile(true)
        workspace.activate(.side)
        let original = workspace.lease
        workspace.markActivationClick()
        workspace.activate(.front)
        workspace.activate(.side)
        XCTAssertFalse(workspace.admitsPrimaryPress(clickCount: 1, lease: original))
        XCTAssertTrue(workspace.admitsPrimaryPress(clickCount: 2, lease: workspace.lease))
        let dual = workspace.lease
        workspace.markActivationClick()
        workspace.setDualProfile(false)
        XCTAssertFalse(workspace.admitsPrimaryPress(clickCount: 1, lease: dual))
        XCTAssertTrue(workspace.admitsPrimaryPress(clickCount: 2, lease: workspace.lease))
    }
}
