import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

@MainActor
final class CanvasProfileStoreTests: XCTestCase {
    func testCompanionActivationRequiresCurrentDualLeaseAndArmsOnlyPointerFollowThrough() throws {
        let store = EditorStore()
        defer { store.stop() }
        let singleLease = store.canvasProfiles.lease
        XCTAssertNil(store.activateCanvasCompanion(plane: .side, expectedLease: singleLease))

        store.setDualCanvasProfile(true)
        let frontLease = store.canvasProfiles.lease
        XCTAssertNil(store.activateCanvasCompanion(plane: .side, expectedLease: singleLease))
        XCTAssertNil(store.activateCanvasCompanion(plane: .front, expectedLease: frontLease))

        let sideLease = try XCTUnwrap(store.activateCanvasCompanion(plane: .side, expectedLease: frontLease))
        XCTAssertEqual(store.plane, .side)
        XCTAssertFalse(store.admitsCanvasPrimaryPress(clickCount: 1, lease: frontLease))
        XCTAssertFalse(store.admitsCanvasPrimaryPress(clickCount: 2, lease: sideLease))
        XCTAssertTrue(store.admitsCanvasPrimaryPress(clickCount: 1, lease: sideLease))
        XCTAssertTrue(store.admitsCanvasPrimaryPress(clickCount: 2, lease: sideLease))

        store.plane = .front
        XCTAssertTrue(store.admitsCanvasPrimaryPress(clickCount: 2, lease: store.canvasProfiles.lease))
        XCTAssertFalse(store.canUndo)
    }

    func testOldProfileCannotRegisterOrReleaseNewActiveCanvasContext() {
        let store = EditorStore()
        defer { store.stop() }
        let frontLease = store.canvasProfiles.lease
        let front = CanvasProjection(bounds: store.bounds, plane: .front, width: 420, height: 240)
        store.setCanvasContext(projection: front, width: 420, height: 240, lease: frontLease)
        XCTAssertTrue(store.ownsCanvasProfile(frontLease))
        XCTAssertEqual(store.canvasHeight, 240)

        store.setDualCanvasProfile(true)
        XCTAssertFalse(store.ownsCanvasProfile(frontLease))
        let dualFrontLease = store.canvasProfiles.lease
        store.plane = .side
        let sideLease = store.canvasProfiles.lease
        XCTAssertEqual(store.canvasProfiles.activePlane, .side)
        XCTAssertFalse(store.ownsCanvasProfile(dualFrontLease))
        XCTAssertTrue(store.ownsCanvasProfile(sideLease))

        let side = CanvasProjection(bounds: store.bounds, plane: .side, width: 350, height: 180)
        store.setCanvasContext(projection: side, width: 350, height: 180, lease: sideLease)
        XCTAssertEqual(store.canvasHeight, 180)
        store.setCanvasContext(projection: front, width: 420, height: 240, lease: frontLease)
        store.releaseCanvasProfile(lease: dualFrontLease)
        XCTAssertEqual(store.canvasHeight, 180)
        XCTAssertTrue(store.ownsCanvasProfile(sideLease))

        store.releaseCanvasProfile(lease: sideLease)
        XCTAssertFalse(store.ownsCanvasProfile(sideLease))
        store.setCanvasContext(projection: side, width: 350, height: 180, lease: sideLease)
        XCTAssertEqual(store.canvasHeight, 0)
    }
}
