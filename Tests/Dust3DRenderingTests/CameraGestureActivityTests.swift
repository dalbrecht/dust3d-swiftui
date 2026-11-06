import XCTest

@testable import Dust3DRendering

final class CameraGestureActivityTests: XCTestCase {
    func testContinuousPhasesRemainActiveAcrossGestureReinterpretation() {
        var activity = CameraGestureActivity()
        XCTAssertFalse(activity.isActive)
        for phase in [CameraGestureActivity.Phase.mayBegin, .began, .changed, .stationary, .changed] {
            activity.update(phase)
            XCTAssertTrue(activity.isActive)
        }
    }

    func testTerminalAndOneShotPhasesClearActivity() {
        for phase in [CameraGestureActivity.Phase.ended, .cancelled, .none] {
            var activity = CameraGestureActivity()
            activity.update(.began)
            activity.update(phase)
            XCTAssertFalse(activity.isActive)
        }
    }

    func testAutomaticOrbitPausesDuringGestureAndResumesAfterEnding() {
        var activity = CameraGestureActivity()
        var availability = AutomaticOrbitAvailability(
            requested: true, reduceMotion: false, hasWindow: true, isVisible: true,
            isKeyWindow: true, isAppActive: true, hasRenderer: true, isDragging: false)
        XCTAssertTrue(availability.canAnimate)
        activity.update(.changed)
        availability.isDragging = activity.isActive
        XCTAssertFalse(availability.canAnimate)
        activity.update(.ended)
        availability.isDragging = activity.isActive
        XCTAssertTrue(availability.canAnimate)
    }

    func testLifecycleCancellationClearsActivityAndAllowsNextGesture() {
        var activity = CameraGestureActivity()
        activity.update(.changed)
        activity.cancel()
        XCTAssertFalse(activity.isActive)
        activity.cancel()
        activity.update(.mayBegin)
        XCTAssertTrue(activity.isActive)
    }
}
