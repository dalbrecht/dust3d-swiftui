import XCTest

@testable import Dust3DEditorModel

final class AnimationPCMPlaybackTests: XCTestCase {
    func testRenderedFrameProjectsThePoseAndReturnsActualPcm() throws {
        let timeline = try AnimationTimeline(sampleTimes: [0, 0.125, 0.25, 0.5], duration: 0.5, loops: false)
        var samples = [Int16](repeating: 0, count: 22_050)
        samples[5_512] = 1_200
        samples[5_513] = -800
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: samples)
        let impact = try playback.position(atRenderedFrame: 5_512)
        XCTAssertEqual(impact.pcmFrameOffset, 5_512)
        XCTAssertEqual(impact.pose.sampleIndex, 0)
        XCTAssertLessThan(impact.pose.seconds, 0.125)
        XCTAssertEqual(try playback.position(atRenderedFrame: 5_513).pose.sampleIndex, 1)
        XCTAssertEqual(try playback.position(atRenderedFrame: 13_000).pose.sampleIndex, 2)

        let slice: ArraySlice<Int16> = try playback.samples(atRenderedFrame: 5_512, maximumFrames: 2)
        XCTAssertEqual(slice.startIndex, 5_512)
        XCTAssertEqual(Array(slice), [1_200, -800])
        samples[5_512] = 0
        XCTAssertEqual(slice.first, 1_200)
        XCTAssertEqual(try playback.samples(atRenderedFrame: 5_512, maximumFrames: 1).first, 1_200)
    }

    func testNonloopClampsToTerminalPoseAndHasNoRemainingPcm() throws {
        let duration = 4.5 / 44_100
        let timeline = try AnimationTimeline(
            sampleTimes: [0, 2.0 / 44_100, duration], duration: duration, loops: false)
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: [1, 2, 3, 4])
        XCTAssertEqual(Array(try playback.samples(atRenderedFrame: 3, maximumFrames: 4)), [4])
        let last = try playback.position(atRenderedFrame: 3)
        XCTAssertEqual(last.pcmFrameOffset, 3)
        XCTAssertEqual(last.pose.sampleIndex, 1)
        XCTAssertFalse(last.pose.isFinished)
        for frame: UInt64 in [4, .max] {
            let end = try playback.position(atRenderedFrame: frame)
            XCTAssertNil(end.pcmFrameOffset)
            XCTAssertEqual(end.pose.sampleIndex, 2)
            XCTAssertEqual(end.pose.seconds, duration)
            XCTAssertTrue(end.pose.isFinished)
            XCTAssertTrue(try playback.samples(atRenderedFrame: frame, maximumFrames: 4).isEmpty)
        }
    }

    func testLoopWrapUsesWholePcmFramesAndEachSliceStopsAtTheSeam() throws {
        let duration = 8.5 / 44_100
        let timeline = try AnimationTimeline(
            sampleTimes: [0, 2.0 / 44_100, 5.0 / 44_100, duration], duration: duration, loops: true)
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: [1, 2, 3, 4, 5, 6, 7, 8])
        let largeOffset = try playback.position(atRenderedFrame: .max)
        XCTAssertEqual(largeOffset.pcmFrameOffset, 7)
        XCTAssertEqual(largeOffset.pose.sampleIndex, 2)
        XCTAssertFalse(largeOffset.pose.isFinished)
        XCTAssertEqual(Array(try playback.samples(atRenderedFrame: 6, maximumFrames: 8)), [7, 8])
        let wrapped = try playback.position(atRenderedFrame: 8)
        XCTAssertEqual(wrapped.pcmFrameOffset, 0)
        XCTAssertEqual(wrapped.pose.sampleIndex, 0)
        XCTAssertEqual(wrapped.pose.seconds, 0)
        XCTAssertEqual(Array(try playback.samples(atRenderedFrame: 8, maximumFrames: 2)), [1, 2])
    }

    func testSeekKeepsTheRequestedPoseAndReturnsItsQuantizedPcmOffset() throws {
        let timeline = try AnimationTimeline(sampleTimes: [0, 0.125, 0.5], duration: 0.5, loops: true)
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: .init(repeating: 0, count: 22_050))
        let seek = try playback.seek(to: 0.125)
        XCTAssertEqual(seek.pose.seconds, 0.125)
        XCTAssertEqual(seek.pose.sampleIndex, 1)
        XCTAssertEqual(seek.pcmFrameOffset, 5_512)
        let end = try playback.seek(to: 0.5)
        XCTAssertEqual(end.pose.sampleIndex, 2)
        XCTAssertFalse(end.pose.isFinished)
        XCTAssertNil(end.pcmFrameOffset)
        XCTAssertEqual(try playback.position(atRenderedFrame: 22_050).pcmFrameOffset, 0)
    }

    func testSeekRespectsExactAudioFrameBoundaries() throws {
        let timeline = try AnimationTimeline(sampleTimes: [0, 1], duration: 1, loops: false)
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: .init(repeating: 0, count: 44_100))

        for frame in [5, 15] {
            let start = try playback.position(atRenderedFrame: UInt64(frame)).pose.seconds
            XCTAssertEqual(try playback.seek(to: start.nextDown).pcmFrameOffset, frame - 1)
            XCTAssertEqual(try playback.seek(to: start).pcmFrameOffset, frame)
            XCTAssertEqual(try playback.seek(to: start.nextUp).pcmFrameOffset, frame)
        }
    }

    func testResumePreservesScrubbedPoseAndWrapsAudioWithoutResettingGroundTime() throws {
        let rate = Double(AnimationPCMPlayback.sampleRate)
        let timeline = try AnimationTimeline(
            sampleTimes: [0, 2.5 / rate, 6 / rate], duration: 6 / rate, loops: true)
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: [1, 2, 3, 4, 5, 6])
        let first = try playback.resume(fromSample: 1, renderedFrames: 0)
        XCTAssertEqual(first.position.pose.sampleIndex, 1)
        XCTAssertEqual(first.position.pcmFrameOffset, 2)
        XCTAssertEqual(first.groundTime, 2.5 / rate)
        XCTAssertEqual(
            Array(try playback.samples(resumingAtSample: 1, renderedFrames: 0, maximumFrames: 2)), [3, 4])
        let seam = try playback.resume(fromSample: 1, renderedFrames: 4)
        XCTAssertEqual(seam.position.pose.sampleIndex, 0)
        XCTAssertEqual(seam.position.pcmFrameOffset, 0)
        XCTAssertEqual(seam.groundTime, 6 / rate, accuracy: 1e-15)
        XCTAssertEqual(
            Array(try playback.samples(resumingAtSample: 1, renderedFrames: 4, maximumFrames: 2)), [1, 2])
        XCTAssertEqual(
            try playback.resume(fromSample: 1, renderedFrames: .max).position.pcmFrameOffset, 5)
    }

    func testLoopGroundTravelUsesTheClipDurationAtEachAudioSeam() throws {
        let rate = Double(AnimationPCMPlayback.sampleRate)
        let duration = 4.5 / rate
        let timeline = try AnimationTimeline(
            sampleTimes: [0, 2.5 / rate, duration], duration: duration, loops: true)
        for count in [4, 5] {
            let playback = try AnimationPCMPlayback(timeline: timeline, samples: .init(repeating: 0, count: count))
            let cycles = 1_000
            let frames = UInt64(cycles * count - 2)
            let seam = try playback.resume(fromSample: 1, renderedFrames: frames)
            XCTAssertEqual(seam.position.pcmFrameOffset, 0)
            XCTAssertEqual(seam.position.pose.sampleIndex, 0)
            XCTAssertEqual(seam.groundTime, Double(cycles) * duration, accuracy: 1e-12)
            let fromStart = try playback.project(atRenderedFrame: UInt64(cycles * count))
            XCTAssertEqual(fromStart.position, seam.position)
            XCTAssertEqual(fromStart.groundTime, seam.groundTime)
            let before = try playback.resume(fromSample: 1, renderedFrames: frames - 1)
            let after = try playback.resume(fromSample: 1, renderedFrames: frames + 1)
            XCTAssertLessThan(before.groundTime, seam.groundTime)
            XCTAssertGreaterThan(after.groundTime, seam.groundTime)
        }
    }

    func testResumeAtTheTerminalSampleKeepsItsPoseAndRespectsLoopPolicy() throws {
        let rate = Double(AnimationPCMPlayback.sampleRate)
        let duration = 4.5 / rate
        for loops in [false, true] {
            let timeline = try AnimationTimeline(
                sampleTimes: [0, 2 / rate, duration], duration: duration, loops: loops)
            let playback = try AnimationPCMPlayback(timeline: timeline, samples: [1, 2, 3, 4])
            let terminal = try playback.resume(fromSample: 2, renderedFrames: 0)
            XCTAssertEqual(terminal.position.pose.sampleIndex, 2)
            XCTAssertEqual(terminal.position.pcmFrameOffset, loops ? 0 : nil)
            XCTAssertEqual(terminal.groundTime, duration)
            let next = try playback.resume(fromSample: 2, renderedFrames: 1)
            XCTAssertEqual(next.position.pose.sampleIndex, loops ? 0 : 2)
            XCTAssertEqual(next.position.pcmFrameOffset, loops ? 1 : nil)
            XCTAssertEqual(next.groundTime, loops ? duration + 1 / rate : duration)
        }
    }

    func testTerminalResumeDoesNotOverflowTheLargestPcmFrameCounter() throws {
        let duration = 1.5 / Double(AnimationPCMPlayback.sampleRate)
        let timeline = try AnimationTimeline(sampleTimes: [0, duration], duration: duration, loops: true)
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: [0])
        let result = try playback.resume(fromSample: 1, renderedFrames: .max)
        XCTAssertEqual(result.position.pcmFrameOffset, 0)
        XCTAssertEqual(result.position.pose.sampleIndex, 0)
        XCTAssertEqual(result.groundTime, Double(UInt64.max) * duration)
    }

    func testNonloopResumeStopsBothPcmAndGroundAtTheEndpoint() throws {
        let rate = Double(AnimationPCMPlayback.sampleRate)
        let duration = 4.5 / rate
        let timeline = try AnimationTimeline(sampleTimes: [0, 2.5 / rate, duration], duration: duration, loops: false)
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: [1, 2, 3, 4])
        XCTAssertEqual(
            Array(try playback.samples(resumingAtSample: 1, renderedFrames: 0, maximumFrames: 4)), [3, 4])
        for count: UInt64 in [2, .max] {
            let end = try playback.resume(fromSample: 1, renderedFrames: count)
            XCTAssertTrue(end.position.pose.isFinished)
            XCTAssertEqual(end.groundTime, duration)
            XCTAssertTrue(try playback.samples(resumingAtSample: 1, renderedFrames: count, maximumFrames: 4).isEmpty)
        }
        XCTAssertThrowsError(try playback.resume(fromSample: -1, renderedFrames: 0))
        XCTAssertThrowsError(try playback.samples(resumingAtSample: 3, renderedFrames: 0, maximumFrames: 4))
    }

    func testInvalidAudioAndSliceSizesThrowWithoutClamping() throws {
        let duration = 4.0 / 44_100
        let timeline = try AnimationTimeline(sampleTimes: [0, duration], duration: duration, loops: false)
        XCTAssertThrowsError(try AnimationPCMPlayback(timeline: timeline, samples: [])) {
            XCTAssertEqual($0 as? AnimationPCMPlaybackError, .invalidSampleCount)
        }
        XCTAssertThrowsError(try AnimationPCMPlayback(timeline: timeline, samples: [1, 2])) {
            XCTAssertEqual($0 as? AnimationPCMPlaybackError, .durationMismatch)
        }
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: [1, 2, 3, 4])
        for maximumFrames in [0, -1, Int.max] {
            XCTAssertThrowsError(try playback.samples(atRenderedFrame: 0, maximumFrames: maximumFrames)) {
                XCTAssertEqual($0 as? AnimationPCMPlaybackError, .invalidSliceSize)
            }
        }
        for seconds in [-0.01, .nan, .infinity, 1] {
            XCTAssertThrowsError(try playback.seek(to: seconds)) {
                XCTAssertEqual($0 as? AnimationTimelineError, .invalidTime)
            }
        }
    }
}
