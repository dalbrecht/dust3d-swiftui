import Dust3DEditorModel
import Foundation

enum ExperimentalAnimationAudioError: LocalizedError, Equatable {
    case unavailable, retired, underrun, clockReset

    var errorDescription: String? {
        switch self {
        case .unavailable: "The animation audio output could not be prepared."
        case .retired: "The animation audio source is no longer current."
        case .underrun: "The audio output ran out of queued animation samples."
        case .clockReset: "The audio playback clock reset."
        }
    }
}

/// Keeps a bounded amount of supplied PCM ahead of one rendered sample clock.
struct SuppliedAnimationPCMQueue {
    private var scheduled: UInt64 = 0
    private var lastRendered: UInt64 = 0
    private var reachedEnd = false
    private static let chunkSize = AnimationPCMPlayback.maximumSliceFrames
    private static let lookahead = UInt64(chunkSize * 4)

    mutating func refill(
        after rendered: UInt64?, read: (UInt64, Int) throws -> ArraySlice<Int16>?,
        enqueue: (ArraySlice<Int16>) throws -> Void
    ) throws -> UInt64 {
        // A missing device timestamp leaves the most recent presentation intact.
        guard let rendered else { return lastRendered }
        guard rendered >= lastRendered else { throw ExperimentalAnimationAudioError.clockReset }
        guard reachedEnd || rendered <= scheduled else { throw ExperimentalAnimationAudioError.underrun }
        let horizon = min(rendered, UInt64.max - Self.lookahead) + Self.lookahead
        while scheduled < horizon, !reachedEnd {
            let count = Int(min(UInt64(Self.chunkSize), horizon - scheduled))
            guard let samples = try read(scheduled, count) else { throw ExperimentalAnimationAudioError.retired }
            if samples.isEmpty {
                reachedEnd = true
                break
            }
            guard samples.count <= count else { throw ExperimentalAnimationAudioError.unavailable }
            try enqueue(samples)
            scheduled += UInt64(samples.count)
        }
        lastRendered = min(rendered, scheduled)
        return lastRendered
    }
}

#if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import AVFAudio

    /// Owns one device playback clock. Its reader is already scoped to one clip and playback token.
    @MainActor
    final class ExperimentalAnimationAudioOutput {
        private let engine = AVAudioEngine()
        private let player = AVAudioPlayerNode()
        private let format: AVAudioFormat
        private let read: (UInt64, Int) throws -> ArraySlice<Int16>?
        private var queue = SuppliedAnimationPCMQueue()
        private var started = false

        init(read: @escaping (UInt64, Int) throws -> ArraySlice<Int16>?) throws {
            guard
                let format = AVAudioFormat(
                    standardFormatWithSampleRate: Double(AnimationPCMPlayback.sampleRate), channels: 1)
            else { throw ExperimentalAnimationAudioError.unavailable }
            self.format = format
            self.read = read
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }

        func start() throws {
            _ = try refill(after: 0)
            try engine.start()
            player.play()
            started = true
        }

        func stop() {
            player.stop()
            engine.stop()
            started = false
        }

        func renderedFrames() throws -> UInt64 {
            guard started else { return 0 }
            guard let nodeTime = player.lastRenderTime, let time = player.playerTime(forNodeTime: nodeTime)
            else { return try refill(after: nil) }
            guard time.isSampleTimeValid, time.sampleRate == format.sampleRate, time.sampleTime >= 0
            else { throw ExperimentalAnimationAudioError.unavailable }
            return try refill(after: UInt64(time.sampleTime))
        }

        private func refill(after rendered: UInt64?) throws -> UInt64 {
            try queue.refill(
                after: rendered, read: read,
                enqueue: { [format, player] samples in
                    guard
                        let buffer = AVAudioPCMBuffer(
                            pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                        let channel = buffer.floatChannelData?[0]
                    else { throw ExperimentalAnimationAudioError.unavailable }
                    buffer.frameLength = AVAudioFrameCount(samples.count)
                    for (index, sample) in samples.enumerated() {
                        channel[index] = Float(sample) / 32_768
                    }
                    player.scheduleBuffer(buffer, completionHandler: nil)
                })
        }
    }
#endif
