import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class AnimationPCMQueueTests: XCTestCase {
    func testQueueKeepsFourBoundedChunksAheadAndRejectsAnUnderrun() throws {
        var queue = SuppliedAnimationPCMQueue()
        var ranges: [Range<UInt64>] = []
        let source = Array(repeating: Int16(42), count: 4_096)
        func read(_ offset: UInt64, _ maximum: Int) -> ArraySlice<Int16>? {
            ranges.append(offset..<(offset + UInt64(maximum)))
            return source.prefix(maximum)
        }

        XCTAssertEqual(try queue.refill(after: 0, read: read, enqueue: { _ in }), 0)
        XCTAssertEqual(ranges, [0..<4_096, 4_096..<8_192, 8_192..<12_288, 12_288..<16_384])
        XCTAssertEqual(try queue.refill(after: 1_024, read: read, enqueue: { _ in }), 1_024)
        XCTAssertEqual(ranges.last, 16_384..<17_408)
        XCTAssertThrowsError(try queue.refill(after: 17_409, read: read, enqueue: { _ in })) {
            XCTAssertEqual($0 as? ExperimentalAnimationAudioError, .underrun)
        }
    }

    func testQueueRejectsARewoundAudioClockWithoutReadingOrEnqueueing() throws {
        var queue = SuppliedAnimationPCMQueue()
        let source = Array(repeating: Int16(42), count: 4_096)
        func read(_ offset: UInt64, _ maximum: Int) -> ArraySlice<Int16>? {
            source.prefix(maximum)
        }
        XCTAssertEqual(try queue.refill(after: 0, read: read, enqueue: { _ in }), 0)
        XCTAssertEqual(try queue.refill(after: 1_024, read: read, enqueue: { _ in }), 1_024)
        func noRead(_ offset: UInt64, _ maximum: Int) -> ArraySlice<Int16>? {
            XCTFail("Missing or rewound clocks must not read PCM")
            return nil
        }
        func noEnqueue(_ samples: ArraySlice<Int16>) {
            XCTFail("Missing or rewound clocks must not enqueue PCM")
        }
        XCTAssertEqual(try queue.refill(after: nil, read: noRead, enqueue: noEnqueue), 1_024)
        XCTAssertThrowsError(try queue.refill(after: 512, read: noRead, enqueue: noEnqueue)) {
            XCTAssertEqual($0 as? ExperimentalAnimationAudioError, .clockReset)
        }
        XCTAssertEqual(try queue.refill(after: nil, read: noRead, enqueue: noEnqueue), 1_024)
        XCTAssertEqual(try queue.refill(after: 2_048, read: read, enqueue: { _ in }), 2_048)
    }

    func testShortLoopFillsFourBuffersInOrderAcrossEverySeam() throws {
        let rate = Double(AnimationPCMPlayback.sampleRate)
        let duration = 3 / rate
        let timeline = try AnimationTimeline(
            sampleTimes: [0, 1 / rate, duration], duration: duration, loops: true)
        let playback = try AnimationPCMPlayback(timeline: timeline, samples: [11, 22, 33])
        var queue = SuppliedAnimationPCMQueue()
        var buffers: [[Int16]] = []
        var reads = 0
        XCTAssertEqual(
            try queue.refill(
                after: 0,
                read: { offset, maximum in
                    reads += 1
                    return try playback.scheduledSamples(
                        atRenderedFrame: offset, maximumFrames: maximum, resumingAtSample: 1)
                },
                enqueue: { buffers.append(Array($0)) }), 0)
        XCTAssertEqual(reads, 4)
        XCTAssertEqual(buffers.map(\.count), [4096, 4096, 4096, 4096])
        let expected: [Int16] = [22, 33, 11]
        XCTAssertEqual(buffers.flatMap { $0 }, (0..<16_384).map { expected[$0 % expected.count] })
    }

    func testQueueClampsToTheEndAndDoesNotReadPastIt() throws {
        var queue = SuppliedAnimationPCMQueue()
        var reads = 0
        let source: [Int16] = [1, 2, 3]
        func read(_ offset: UInt64, _ maximum: Int) -> ArraySlice<Int16>? {
            reads += 1
            return source.dropFirst(Int(offset)).prefix(maximum)
        }

        var enqueued: [Int16] = []
        XCTAssertEqual(try queue.refill(after: 0, read: read, enqueue: { enqueued += $0 }), 0)
        XCTAssertEqual(enqueued, source)
        XCTAssertEqual(try queue.refill(after: 100, read: read, enqueue: { _ in }), 3)
        XCTAssertEqual(reads, 2)
    }
}
