import Foundation
import XCTest

@testable import Dust3DRendering

final class AutomaticOrbitTests: XCTestCase {
    func testEveryVisibilityMotionAndInteractionBoundaryPausesTheTurntable() {
        let ready = AutomaticOrbitAvailability(
            requested: true, reduceMotion: false, hasWindow: true, isVisible: true,
            isKeyWindow: true, isAppActive: true, hasRenderer: true, isDragging: false)
        XCTAssertTrue(ready.canAnimate)
        for key in [
            \AutomaticOrbitAvailability.requested, \.hasWindow, \.isVisible,
            \.isKeyWindow, \.isAppActive, \.hasRenderer,
        ] {
            var paused = ready
            paused[keyPath: key] = false
            XCTAssertFalse(paused.canAnimate)
        }
        var reduced = ready
        reduced.reduceMotion = true
        XCTAssertFalse(reduced.canAnimate)
        var dragging = ready
        dragging.isDragging = true
        XCTAssertFalse(dragging.canAnimate)
    }

    func testElapsedTimeMatchesQtRateIndependentOfCallbackFrequency() {
        for (interval, count) in [(0.042, 25), (0.021, 50), (0.105, 10)] {
            var timeline = AutomaticOrbitTimeline()
            XCTAssertEqual(timeline.delta(at: 10), 0)
            var total: Float = 0
            for index in 1...count { total += timeline.delta(at: 10 + Double(index) * interval) }
            XCTAssertEqual(total, -.pi / 360 * 25, accuracy: 0.000001)
        }
    }

    func testPauseResetAndLongSchedulingGapsNeverCatchUpOrRotateBackward() {
        var timeline = AutomaticOrbitTimeline()
        XCTAssertEqual(timeline.delta(at: 0), 0)
        XCTAssertEqual(timeline.delta(at: 0.042), -.pi / 360, accuracy: 0.000001)
        timeline.reset()
        XCTAssertEqual(timeline.delta(at: 100), 0)
        XCTAssertEqual(timeline.delta(at: 100.042), -.pi / 360, accuracy: 0.000001)
        XCTAssertEqual(timeline.delta(at: 200), 0)
        XCTAssertEqual(timeline.delta(at: 200.042), -.pi / 360, accuracy: 0.000001)
        XCTAssertEqual(timeline.delta(at: 1), 0)
        XCTAssertEqual(timeline.delta(at: 1.042), -.pi / 360, accuracy: 0.000001)
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(timeline.delta(at: invalid), 0)
            XCTAssertEqual(timeline.delta(at: 2), 0)
            XCTAssertEqual(timeline.delta(at: 2.042), -.pi / 360, accuracy: 0.000001)
        }
    }
}

@MainActor
final class AutomaticOrbitDriverTests: XCTestCase {
    func testTimerPausesWhenEligibilityChangesAndResumesWithoutCatchUp() async throws {
        var allowed = true
        var now: TimeInterval = 0
        var samples: [Float] = []
        let driver = AutomaticOrbitDriver(
            canAnimate: { allowed }, advance: { samples.append($0) }, now: { now })
        defer { driver.stop() }
        driver.reconcile()
        let firstTask = try XCTUnwrap(driver.task)
        now = 0.042
        try await waitUntil { !samples.isEmpty }
        XCTAssertEqual(samples.reduce(0, +), -.pi / 360, accuracy: 0.000001)
        allowed = false
        try await waitUntil { driver.task == nil }
        await firstTask.value
        let pausedCount = samples.count
        now = 100
        driver.reconcile()
        XCTAssertNil(driver.task)
        XCTAssertEqual(samples.count, pausedCount)
        allowed = true
        driver.reconcile()
        let resumed = try XCTUnwrap(driver.task)
        now = 100.042
        try await waitUntil { samples.count > pausedCount }
        XCTAssertEqual(samples.last ?? 0, -.pi / 360, accuracy: 0.000001)
        driver.stop()
        await resumed.value
        XCTAssertNil(driver.task)
        XCTAssertEqual(samples.count, pausedCount + 1)
    }

    func testScheduledTaskDoesNotRetainItsDriverOrInvokeAfterDeallocation() async {
        var samples: [Float] = []
        var driver: AutomaticOrbitDriver? = AutomaticOrbitDriver(
            canAnimate: { true }, advance: { samples.append($0) })
        weak var weakDriver: AutomaticOrbitDriver?
        weakDriver = driver
        driver?.reconcile()
        let task = driver?.task
        driver = nil
        XCTAssertNil(weakDriver)
        await task?.value
        XCTAssertTrue(samples.isEmpty)
    }

    func testResetForDirectCameraInputStartsANewTimingInterval() async throws {
        var now: TimeInterval = 0
        var samples: [Float] = []
        let driver = AutomaticOrbitDriver(canAnimate: { true }, advance: { samples.append($0) }, now: { now })
        defer { driver.stop() }
        driver.reconcile()
        now = 0.042
        try await waitUntil { samples.count == 1 }
        now = 100
        driver.resetTiming()
        now = 100.021
        try await waitUntil { samples.count == 2 }
        XCTAssertEqual(samples[1], -.pi / 720, accuracy: 0.000001)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Automatic orbit scheduler did not reach the expected state")
    }
}
