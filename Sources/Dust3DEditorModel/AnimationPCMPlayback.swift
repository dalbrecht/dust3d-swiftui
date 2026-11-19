/// Admission failures for the supplied mono PCM span and requested slice length.
public enum AnimationPCMPlaybackError: Error, Equatable, Sendable {
    case invalidSampleCount, durationMismatch, invalidSliceSize
}

/// A pose on the shared clip clock and the offset of its next available PCM frame.
public struct AnimationPCMPlaybackPosition: Equatable, Sendable {
    public let pose: AnimationTimelinePosition
    public let pcmFrameOffset: Int?

    package init(pose: AnimationTimelinePosition, pcmFrameOffset: Int?) {
        self.pose = pose
        self.pcmFrameOffset = pcmFrameOffset
    }
}

/// Projects caller-supplied pose times and signed mono PCM16 on one frame clock.
public struct AnimationPCMPlayback: Sendable {
    public static let sampleRate = 44_100
    public static let maximumSampleCount = 30 * sampleRate
    public static let maximumSliceFrames = 4_096

    private let timeline: AnimationTimeline
    private let pcm: [Int16]

    /// Admit a nonempty mono buffer of up to 30 seconds at 44.1 kHz.
    /// The PCM and pose durations must differ by less than one audio frame to accommodate quantization.
    /// The value retains Swift array storage and leaves caller mutation isolated by copy-on-write.
    public init(timeline: AnimationTimeline, samples: [Int16]) throws {
        guard (1...Self.maximumSampleCount).contains(samples.count) else {
            throw AnimationPCMPlaybackError.invalidSampleCount
        }
        guard timeline.duration <= 30, abs(timeline.duration * Double(Self.sampleRate) - Double(samples.count)) < 1
        else {
            throw AnimationPCMPlaybackError.durationMismatch
        }
        self.timeline = timeline
        pcm = samples
    }

    /// A copy-on-write snapshot of the complete admitted mono clip for encoding.
    package var wavSamples: [Int16] { pcm }

    /// Project the next frame after the supplied number of rendered PCM frames.
    /// Select the latest pose at the audio frame's start time. A fractional-frame contact can begin
    /// one audio frame before its pose transition. Loops use the integral PCM length as their period.
    /// Nonloop playback reaches the terminal pose at the PCM endpoint and has no remaining audio.
    public func position(atRenderedFrame renderedFrame: UInt64) throws -> AnimationPCMPlaybackPosition {
        let offset = frameOffset(atRenderedFrame: renderedFrame)
        let seconds =
            offset.map { min(Double($0) / Double(Self.sampleRate), timeline.duration.nextDown) }
            ?? timeline.duration
        return AnimationPCMPlaybackPosition(pose: try timeline.scrub(to: seconds), pcmFrameOffset: offset)
    }

    /// Project pose, audio, and unwrapped ground travel from the same rendered frame.
    package func project(atRenderedFrame frame: UInt64) throws -> (
        position: AnimationPCMPlaybackPosition, groundTime: Double
    ) {
        let position = try position(atRenderedFrame: frame)
        let phase = position.pose.seconds
        let groundTime = timeline.loops ? loopGroundTime(renderedFrames: frame, startingAt: 0, phase: phase) : phase
        return (position, groundTime)
    }

    /// Project an explicit seek at the requested pose time and round the audio offset down to a frame.
    /// Seeking to the terminal pose has no PCM offset, including for looping clips.
    /// Throws `AnimationTimelineError.invalidTime` for a time outside the clip.
    public func seek(to seconds: Double) throws -> AnimationPCMPlaybackPosition {
        let pose = try timeline.scrub(to: seconds)
        let rate = Double(Self.sampleRate)
        var offset = Int(seconds * rate)
        // Multiplication can round across a frame start. Compare using the
        // same timestamp representation as position(atRenderedFrame:).
        if seconds < Double(offset) / rate {
            offset -= 1
        } else if seconds >= Double(offset + 1) / rate {
            offset += 1
        }
        return AnimationPCMPlaybackPosition(
            pose: pose, pcmFrameOffset: seconds < timeline.duration && offset < pcm.count ? offset : nil)
    }

    /// Borrow the next contiguous PCM samples through a copy-on-write slice.
    /// Requests accept 1 through 4,096 frames and stop at a loop seam or the end of a nonloop clip.
    /// Call again at the next rendered frame to continue a looping clip across its seam.
    public func samples(atRenderedFrame renderedFrame: UInt64, maximumFrames: Int) throws -> ArraySlice<Int16> {
        guard (1...Self.maximumSliceFrames).contains(maximumFrames) else {
            throw AnimationPCMPlaybackError.invalidSliceSize
        }
        let start = frameOffset(atRenderedFrame: renderedFrame) ?? pcm.endIndex
        let end = start + min(maximumFrames, pcm.endIndex - start)
        return pcm[start..<end]
    }

    /// Resume from a discrete scrub selection. The first pose uses the exact
    /// sample timestamp while audio starts at its quantized PCM frame.
    package func resume(fromSample index: Int, renderedFrames: UInt64) throws -> (
        position: AnimationPCMPlaybackPosition, groundTime: Double
    ) {
        let sampleTime = try timeline.sampleTime(at: index)
        let seek = try seek(to: sampleTime)
        let frame = resumedFrame(start: seek.pcmFrameOffset, renderedFrames: renderedFrames)
        let projected = try position(atRenderedFrame: frame)
        let position =
            renderedFrames == 0
            ? AnimationPCMPlaybackPosition(pose: seek.pose, pcmFrameOffset: projected.pcmFrameOffset)
            : projected
        let groundTime: Double
        if renderedFrames == 0 {
            groundTime = sampleTime
        } else if timeline.loops {
            groundTime = loopGroundTime(
                renderedFrames: renderedFrames, startingAt: UInt64(seek.pcmFrameOffset ?? pcm.count),
                phase: position.pose.seconds)
        } else {
            let elapsed = sampleTime + Double(renderedFrames) / Double(Self.sampleRate)
            groundTime = position.pose.isFinished ? timeline.duration : min(elapsed, timeline.duration)
        }
        return (position, groundTime)
    }

    private func loopGroundTime(renderedFrames: UInt64, startingAt start: UInt64, phase: Double) -> Double {
        let count = UInt64(pcm.count)
        // Count PCM wraps exactly, then advance each by the authored pose duration.
        // Split the sum so even a frame counter at UInt64.max can include a scrub anchor.
        let completed = renderedFrames / count
        let carry = (start + renderedFrames % count) / count
        return (Double(completed) + Double(carry)) * timeline.duration + phase
    }

    package func samples(resumingAtSample index: Int, renderedFrames: UInt64, maximumFrames: Int)
        throws -> ArraySlice<Int16>
    {
        let seek = try seek(to: timeline.sampleTime(at: index))
        let frame = resumedFrame(start: seek.pcmFrameOffset, renderedFrames: renderedFrames)
        return try samples(atRenderedFrame: frame, maximumFrames: maximumFrames)
    }

    /// Fill one device buffer across loop seams, borrowing the original slice when it already fits.
    package func scheduledSamples(
        atRenderedFrame frame: UInt64, maximumFrames: Int, resumingAtSample index: Int? = nil
    ) throws -> ArraySlice<Int16> {
        let first =
            if let index {
                try samples(resumingAtSample: index, renderedFrames: frame, maximumFrames: maximumFrames)
            } else {
                try samples(atRenderedFrame: frame, maximumFrames: maximumFrames)
            }
        guard timeline.loops, first.count < maximumFrames else { return first }

        var chunk: [Int16] = []
        chunk.reserveCapacity(maximumFrames)
        chunk.append(contentsOf: first)
        while chunk.count < maximumFrames {
            chunk.append(contentsOf: pcm.prefix(maximumFrames - chunk.count))
        }
        return chunk[...]
    }

    private func resumedFrame(start: Int?, renderedFrames: UInt64) -> UInt64 {
        let count = UInt64(pcm.count)
        let start = UInt64(start ?? pcm.count)
        if timeline.loops { return (start + renderedFrames % count) % count }
        return start + min(renderedFrames, count - start)
    }

    private func frameOffset(atRenderedFrame renderedFrame: UInt64) -> Int? {
        let count = UInt64(pcm.count)
        if timeline.loops { return Int(renderedFrame % count) }
        return renderedFrame < count ? Int(renderedFrame) : nil
    }
}
