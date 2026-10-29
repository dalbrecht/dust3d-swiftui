import XCTest

@testable import Dust3DEditorModel

final class AnimationTimelineTests: XCTestCase {
    func testElapsedTimeSelectsLatestSampleAfterSkippedTicks() throws {
        let timeline = try AnimationTimeline(sampleTimes: [0, 0.1, 0.4, 1], duration: 1, loops: false)
        XCTAssertEqual(try timeline.position(at: 0).sampleIndex, 0)
        XCTAssertEqual(try timeline.position(at: 0.1).sampleIndex, 1)
        XCTAssertEqual(try timeline.position(at: 0.39).sampleIndex, 1)
        XCTAssertEqual(try timeline.position(at: 0.8).sampleIndex, 2)
        let end = try timeline.position(at: 8)
        XCTAssertEqual(end.sampleIndex, 3)
        XCTAssertEqual(end.seconds, 1)
        XCTAssertTrue(end.isFinished)
    }

    func testLoopWrapsAtDurationAndScrubCanReachTerminalSample() throws {
        let timeline = try AnimationTimeline(sampleTimes: [0, 0.5, 1], duration: 1, loops: true)
        XCTAssertEqual(try timeline.position(at: 1).sampleIndex, 0)
        XCTAssertEqual(try timeline.position(at: 2.75).sampleIndex, 1)
        XCTAssertFalse(try timeline.position(at: 2.75).isFinished)
        XCTAssertEqual(try timeline.scrub(to: 1).sampleIndex, 2)
        XCTAssertEqual(try timeline.scrub(to: 1).seconds, 1)
        XCTAssertFalse(try timeline.scrub(to: 1).isFinished)
        XCTAssertEqual(try timeline.position(at: Double.greatestFiniteMagnitude).sampleIndex, 0)
    }

    func testInvalidMetadataAndTimesProduceTypedErrors() throws {
        for times in [[], [0], [0, 0], [0.1, 1], [0, 0.7, 0.6, 1], [0, .nan, 1], [0, .infinity], [0, 2]] {
            XCTAssertThrowsError(try AnimationTimeline(sampleTimes: times, duration: 1, loops: false)) {
                XCTAssertEqual($0 as? AnimationTimelineError, .invalidSamples)
            }
        }
        for duration in [0, -1, .nan, .infinity] {
            XCTAssertThrowsError(try AnimationTimeline(sampleTimes: [0, 1], duration: duration, loops: false)) {
                XCTAssertEqual($0 as? AnimationTimelineError, .invalidDuration)
            }
        }
        let timeline = try AnimationTimeline(sampleTimes: [0, 1], duration: 1, loops: false)
        for time in [-1, .nan, .infinity] {
            XCTAssertThrowsError(try timeline.position(at: time)) {
                XCTAssertEqual($0 as? AnimationTimelineError, .invalidTime)
            }
            XCTAssertThrowsError(try timeline.scrub(to: time))
        }
        XCTAssertThrowsError(try timeline.scrub(to: 1.1))
        XCTAssertFalse(try timeline.position(at: 0).isFinished)
        XCTAssertTrue(try timeline.scrub(to: 1).isFinished)
    }
}
