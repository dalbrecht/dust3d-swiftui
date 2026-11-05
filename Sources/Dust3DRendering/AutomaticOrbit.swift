import Foundation

/// Visibility and interaction boundaries for the opt-in preview turntable.
struct AutomaticOrbitAvailability {
    var requested: Bool
    var reduceMotion: Bool
    var hasWindow: Bool
    var isVisible: Bool
    var isKeyWindow: Bool
    var isAppActive: Bool
    var hasRenderer: Bool
    var isDragging: Bool

    var canAnimate: Bool {
        requested && !reduceMotion && hasWindow && isVisible && isKeyWindow && isAppActive
            && hasRenderer && !isDragging
    }
}

/// Monotonic elapsed-time adapter for Qt's half-degree turn every 42 milliseconds.
struct AutomaticOrbitTimeline {
    private var previousTime: TimeInterval?

    mutating func reset() { previousTime = nil }

    mutating func delta(at time: TimeInterval) -> Float {
        guard time.isFinite else {
            reset()
            return 0
        }
        defer { previousTime = time }
        guard let previousTime else { return 0 }
        let elapsed = time - previousTime
        // A paused app or a long rendering stall must not produce a catch-up jump.
        guard elapsed > 0, elapsed <= 0.25 else { return 0 }
        return Float(-Double.pi / 360 / 0.042 * elapsed)
    }
}

/// Owns one cancellable timer; platform eligibility is rechecked before every camera update.
@MainActor
final class AutomaticOrbitDriver {
    private let canAnimate: () -> Bool
    private let advance: (Float) -> Void
    private let now: () -> TimeInterval
    private var timeline = AutomaticOrbitTimeline()
    private(set) var task: Task<Void, Never>?

    init(
        canAnimate: @escaping () -> Bool, advance: @escaping (Float) -> Void,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.canAnimate = canAnimate
        self.advance = advance
        self.now = now
    }

    func reconcile() {
        guard canAnimate() else {
            stop()
            return
        }
        guard task == nil else { return }
        resetTiming()
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(42)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func resetTiming() {
        timeline.reset()
        _ = timeline.delta(at: now())
    }

    private func tick() {
        guard canAnimate() else {
            stop()
            return
        }
        let delta = timeline.delta(at: now())
        if delta != 0 { advance(delta) }
    }

    func stop() {
        task?.cancel()
        task = nil
        timeline.reset()
    }

    deinit { task?.cancel() }
}
