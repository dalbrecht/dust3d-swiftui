/// Invalid playback metadata and caller times, without native evaluation.
public enum AnimationTimelineError: Error, Equatable, Sendable {
    case invalidDuration, invalidSamples, invalidTime
}

/// One discrete sample chosen from elapsed time, rather than callback count.
public struct AnimationTimelinePosition: Equatable, Sendable {
    public let sampleIndex: Int
    public let seconds: Double
    public let isFinished: Bool
}

/// Pure playback clock projection over already-owned sample times.
/// This does not generate frames or establish a supported native sampling grid.
public struct AnimationTimeline: Sendable {
    private let sampleTimes: [Double]
    public let duration: Double
    public let loops: Bool

    /// Admit finite strictly increasing times spanning exactly zero through duration.
    /// - Parameters:
    ///   - sampleTimes: At least two already-owned sample timestamps, in seconds.
    ///   - duration: Finite positive clip duration, matching the final timestamp.
    ///   - loops: Whether elapsed playback wraps at the terminal timestamp.
    /// - Throws: `AnimationTimelineError.invalidDuration` or `.invalidSamples`.
    /// - Example: `try AnimationTimeline(sampleTimes: [0, 0.5, 1], duration: 1, loops: true)`.
    public init(sampleTimes: [Double], duration: Double, loops: Bool) throws {
        guard duration.isFinite, duration > 0 else { throw AnimationTimelineError.invalidDuration }
        guard sampleTimes.count >= 2, sampleTimes.first == 0, sampleTimes.last == duration else {
            throw AnimationTimelineError.invalidSamples
        }
        var previous = -Double.infinity
        for time in sampleTimes {
            guard time.isFinite, time > previous else { throw AnimationTimelineError.invalidSamples }
            previous = time
        }
        self.sampleTimes = sampleTimes
        self.duration = duration
        self.loops = loops
    }

    /// Select the latest sample at or before elapsed time; skipped callbacks do not accumulate drift.
    /// - Parameter elapsedSeconds: Finite nonnegative elapsed playback time.
    /// - Returns: Wrapped loop phase or clamped nonloop position, with terminal completion state.
    /// - Throws: `AnimationTimelineError.invalidTime` for negative/nonfinite elapsed time.
    /// - Example: `try timeline.position(at: 2.75)`.
    public func position(at elapsedSeconds: Double) throws -> AnimationTimelinePosition {
        guard elapsedSeconds.isFinite, elapsedSeconds >= 0 else { throw AnimationTimelineError.invalidTime }
        // Remainder avoids an overflowing elapsed/duration quotient and any floating-to-integer cast.
        let seconds = loops ? elapsedSeconds.truncatingRemainder(dividingBy: duration) : min(elapsedSeconds, duration)
        return project(seconds: seconds)
    }

    /// Explicit scrubbing can reach the terminal sample even for a looping clip.
    /// - Parameter seconds: Finite time in the closed interval zero through duration.
    /// - Returns: Exact scrub phase and its latest discrete sample; looping scrubs never finish playback.
    /// - Throws: `AnimationTimelineError.invalidTime` outside the admitted interval.
    /// - Example: `try timeline.scrub(to: timeline.duration)`.
    public func scrub(to seconds: Double) throws -> AnimationTimelinePosition {
        guard seconds.isFinite, (0...duration).contains(seconds) else { throw AnimationTimelineError.invalidTime }
        return project(seconds: seconds)
    }

    private func project(seconds: Double) -> AnimationTimelinePosition {
        var lower = 0
        var upper = sampleTimes.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if sampleTimes[middle] <= seconds {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return AnimationTimelinePosition(
            sampleIndex: lower - 1, seconds: seconds, isFinished: !loops && seconds == duration)
    }
}
