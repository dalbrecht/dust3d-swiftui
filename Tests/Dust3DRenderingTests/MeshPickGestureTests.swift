import XCTest

@testable import Dust3DRendering

final class MeshPickGestureTests: XCTestCase {
    func testClickWithinThresholdReturnsReleasePoint() {
        var gesture = MeshPickGesture()
        let lease = MeshPickGesture.Lease(pickingRevision: UUID(), cameraRevision: UUID())
        gesture.begin(at: .zero, lease: lease)
        XCTAssertNil(gesture.drag(to: SIMD2(2, 2), lease: lease))
        XCTAssertEqual(gesture.finish(at: SIMD2(2, 2), lease: lease), SIMD2(2, 2))
        XCTAssertNil(gesture.finish(at: .zero, lease: lease))
    }

    func testThresholdCrossingAppliesFullPressDeltaThenIncrementalDeltas() {
        var gesture = MeshPickGesture()
        let lease = MeshPickGesture.Lease(pickingRevision: UUID(), cameraRevision: UUID())
        gesture.begin(at: SIMD2(10, 10), lease: lease)
        XCTAssertNil(gesture.drag(to: SIMD2(12, 10), lease: lease))
        XCTAssertEqual(gesture.drag(to: SIMD2(14, 10), lease: lease), SIMD2(4, 0))
        XCTAssertEqual(gesture.drag(to: SIMD2(15, 12), lease: lease), SIMD2(1, 2))
        XCTAssertNil(gesture.finish(at: SIMD2(15, 12), lease: lease))
    }

    func testDraggingContinuesAfterOwnCameraRevisionChanges() {
        var gesture = MeshPickGesture()
        let lease = MeshPickGesture.Lease(pickingRevision: UUID(), cameraRevision: UUID())
        gesture.begin(at: .zero, lease: lease)
        XCTAssertEqual(gesture.drag(to: SIMD2(5, 0), lease: lease), SIMD2(5, 0))
        let moved = MeshPickGesture.Lease(pickingRevision: lease.pickingRevision, cameraRevision: UUID())
        XCTAssertEqual(gesture.drag(to: SIMD2(7, 1), lease: moved), SIMD2(2, 1))
        XCTAssertNil(gesture.finish(at: .zero, lease: moved))
    }

    func testDraggedGestureNeverReboundsIntoClick() {
        var gesture = MeshPickGesture()
        let lease = MeshPickGesture.Lease(pickingRevision: UUID(), cameraRevision: UUID())
        gesture.begin(at: .zero, lease: lease)
        XCTAssertEqual(gesture.drag(to: SIMD2(5, 0), lease: lease), SIMD2(5, 0))
        XCTAssertEqual(gesture.drag(to: .zero, lease: lease), SIMD2(-5, 0))
        XCTAssertNil(gesture.finish(at: .zero, lease: lease))
    }

    func testSourceOrCameraLeaseChangeCancelsWithoutABARestoration() {
        for changesCamera in [false, true] {
            var gesture = MeshPickGesture()
            let original = MeshPickGesture.Lease(pickingRevision: UUID(), cameraRevision: UUID())
            let replacement = MeshPickGesture.Lease(
                pickingRevision: changesCamera ? original.pickingRevision : UUID(),
                cameraRevision: changesCamera ? UUID() : original.cameraRevision)
            gesture.begin(at: .zero, lease: original)
            XCTAssertNil(gesture.drag(to: SIMD2(1, 0), lease: replacement))
            XCTAssertNil(gesture.finish(at: .zero, lease: original))
        }
    }

    func testReleaseBeyondThresholdDoesNotPickWithoutDragEvent() {
        var gesture = MeshPickGesture()
        let lease = MeshPickGesture.Lease(pickingRevision: UUID(), cameraRevision: UUID())
        gesture.begin(at: .zero, lease: lease)
        XCTAssertNil(gesture.finish(at: SIMD2(4, 0), lease: lease))
    }

    func testCancelAndMissingPressDoNotPickOrDrag() {
        var gesture = MeshPickGesture()
        let lease = MeshPickGesture.Lease(pickingRevision: UUID(), cameraRevision: UUID())
        XCTAssertNil(gesture.drag(to: .zero, lease: lease))
        gesture.begin(at: .zero, lease: lease)
        gesture.cancel()
        XCTAssertNil(gesture.finish(at: .zero, lease: lease))
        XCTAssertNil(gesture.drag(to: SIMD2(10, 0), lease: lease))
    }
    func testPanIntentBelowThresholdCannotBecomeClickAndResetsOnNextPress() {
        var gesture = MeshPickGesture()
        let lease = MeshPickGesture.Lease(pickingRevision: UUID(), cameraRevision: UUID())
        gesture.begin(at: .zero, lease: lease)
        gesture.disallowClick()
        XCTAssertNil(gesture.drag(to: SIMD2(1, 1), lease: lease))
        XCTAssertNil(gesture.finish(at: SIMD2(1, 1), lease: lease))
        gesture.begin(at: .zero, lease: lease)
        XCTAssertEqual(gesture.finish(at: .zero, lease: lease), .zero)
    }

    func testPanIntentPreservesThresholdAndFullDeltaInsteadOfCancellingDrag() {
        var gesture = MeshPickGesture()
        let lease = MeshPickGesture.Lease(pickingRevision: UUID(), cameraRevision: UUID())
        gesture.begin(at: SIMD2(10, 10), lease: lease)
        gesture.disallowClick()
        XCTAssertNil(gesture.drag(to: SIMD2(12, 10), lease: lease))
        XCTAssertEqual(gesture.drag(to: SIMD2(14, 10), lease: lease), SIMD2(4, 0))
        XCTAssertEqual(gesture.drag(to: SIMD2(15, 12), lease: lease), SIMD2(1, 2))
        XCTAssertNil(gesture.finish(at: SIMD2(10, 10), lease: lease))
    }

}
