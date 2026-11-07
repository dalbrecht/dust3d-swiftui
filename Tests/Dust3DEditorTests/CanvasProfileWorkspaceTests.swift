import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class CanvasProfileWorkspaceTests: XCTestCase {
    func testStartsWithOneFrontProfileAndOwnsItsLease() {
        let workspace = CanvasProfileWorkspace()
        XCTAssertEqual(workspace.activePlane, .front)
        XCTAssertFalse(workspace.isDualProfile)
        XCTAssertEqual(workspace.visiblePlanes, [.front])
        XCTAssertTrue(workspace.owns(workspace.lease))
    }

    func testDualProfileKeepsFixedSlotsAndReturnsToActiveSingleProfile() {
        var workspace = CanvasProfileWorkspace()
        workspace.activate(.side)
        XCTAssertEqual(workspace.visiblePlanes, [.side])
        workspace.setDualProfile(true)
        XCTAssertTrue(workspace.isDualProfile)
        XCTAssertEqual(workspace.activePlane, .side)
        XCTAssertEqual(workspace.visiblePlanes, [.front, .side])
        workspace.activate(.front)
        XCTAssertEqual(workspace.visiblePlanes, [.front, .side])
        workspace.activate(.side)
        workspace.setDualProfile(false)
        XCTAssertFalse(workspace.isDualProfile)
        XCTAssertEqual(workspace.activePlane, .side)
        XCTAssertEqual(workspace.visiblePlanes, [.side])
    }

    func testOnlyChangesRenewLeaseAndReturningDoesNotReviveAnOldLease() {
        var workspace = CanvasProfileWorkspace()
        let original = workspace.lease
        workspace.activate(.front)
        workspace.setDualProfile(false)
        XCTAssertEqual(workspace.lease, original)
        workspace.setDualProfile(true)
        let dualFront = workspace.lease
        XCTAssertFalse(workspace.owns(original))
        workspace.setDualProfile(true)
        XCTAssertTrue(workspace.owns(dualFront))
        workspace.activate(.side)
        let dualSide = workspace.lease
        XCTAssertFalse(workspace.owns(dualFront))
        workspace.activate(.side)
        XCTAssertTrue(workspace.owns(dualSide))
        workspace.activate(.front)
        workspace.setDualProfile(false)
        XCTAssertFalse(workspace.owns(original))
        XCTAssertFalse(workspace.owns(dualFront))
        XCTAssertFalse(workspace.owns(dualSide))
        XCTAssertTrue(workspace.owns(workspace.lease))
    }
}
