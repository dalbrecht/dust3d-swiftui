import Dust3DEditorModel
import Dust3DKit
import Dust3DRendering
import Foundation

struct SuppliedAnimationSource: Equatable, Sendable {
    let playbackRequest: EditorStore.AnimationPlaybackRequest
    let rigRevision: UUID
}

enum SuppliedAnimationClipError: Error, Equatable {
    case sourceMismatch
    case jointOrder
    case payloadLimit
    case matrixCount
    case loopSeam
    case missingAudio
    case invalidGroundMotion
}

/// Owns the copied rest geometry and the supplied poses as one playback input.
/// The producer must associate these values with the same generated rig revision.
struct SuppliedAnimationClip: Sendable {
    let source: SuppliedAnimationSource
    fileprivate let rig: GeneratedRig
    fileprivate let timeline: AnimationTimeline
    fileprivate let pcm: AnimationPCMPlayback?
    fileprivate let groundVelocity: SIMD2<Double>
    fileprivate let restBounds: RenderBounds
    private let matrices: [Double]

    init(
        source: SuppliedAnimationSource, rig: GeneratedRig, jointNames: [String], sampleTimes: [Double],
        duration: Double, loops: Bool, matrices: [Double], pcmSamples: [Int16]? = nil,
        groundVelocity: SIMD2<Double> = .zero
    ) throws {
        let jointCount = rig.joints.count
        guard (1...1024).contains(jointCount), (2...5000).contains(sampleTimes.count),
            matrices.count <= (64 * 1024 * 1024) / MemoryLayout<Double>.stride - sampleTimes.count
        else { throw SuppliedAnimationClipError.payloadLimit }
        guard jointNames.count == jointCount,
            zip(jointNames, rig.joints).allSatisfy({
                !$0.isEmpty && $0.utf8.elementsEqual($1.name.utf8)
            }), Set(jointNames.map { Data($0.utf8) }).count == jointCount
        else { throw SuppliedAnimationClipError.jointOrder }
        let frameWidth = jointCount * 16
        guard matrices.count == frameWidth * sampleTimes.count else { throw SuppliedAnimationClipError.matrixCount }
        if loops, !matrices.prefix(frameWidth).elementsEqual(matrices.suffix(frameWidth)) {
            throw SuppliedAnimationClipError.loopSeam
        }
        guard groundVelocity.x.isFinite, groundVelocity.y.isFinite else {
            throw SuppliedAnimationClipError.invalidGroundMotion
        }
        self.groundVelocity = groundVelocity
        self.source = source
        self.rig = rig
        restBounds = try RenderBounds(vertices: rig.mesh.vertices)
        let timeline = try AnimationTimeline(sampleTimes: sampleTimes, duration: duration, loops: loops)
        self.timeline = timeline
        pcm = try pcmSamples.map { try AnimationPCMPlayback(timeline: timeline, samples: $0) }
        self.matrices = matrices
    }

    fileprivate func pose(at sampleIndex: Int) -> [[Double]] {
        let start = sampleIndex * rig.joints.count * 16
        return rig.joints.indices.map { jointIndex in
            let offset = start + jointIndex * 16
            return Array(matrices[offset..<(offset + 16)])
        }
    }
}

struct SuppliedAnimationWavCapture: Sendable {
    fileprivate let lease: UUID
    fileprivate let source: SuppliedAnimationSource
    let samples: [Int16]
}

enum SuppliedAnimationSample: Sendable {
    case elapsed(Double)
    case resumedElapsed(Double, fromSample: Int)
    case scrub(Double)
    case renderedAudioFrame(UInt64)
    case resumedAudioFrame(UInt64, fromSample: Int)
}

struct SuppliedAnimationFrame: Sendable {
    let playbackPosition: AnimationPCMPlaybackPosition
    let groundOffset: SIMD2<Double>
    let mesh: Mesh
    let lease: UUID
    let restBounds: RenderBounds

    var position: AnimationTimelinePosition { playbackPosition.pose }

    @MainActor
    func viewport(isWireframe: Bool, cameraReset: Int, onError: @escaping (String) -> Void) -> MeshViewport {
        MeshViewport(
            mesh: mesh, isWireframe: isWireframe, cameraReset: cameraReset,
            meshRevision: position.sampleIndex, onError: onError
        ).withAnimationGround(lease: lease, restBounds: restBounds, offset: groundOffset)
    }
}

/// Prepares one displayable frame at a time from caller-owned values.
@MainActor
final class SuppliedAnimationPreview {
    private let skin: @Sendable (GeneratedRig, [[Double]]) async throws -> Mesh
    private var clip: SuppliedAnimationClip?
    private var clipLease: UUID?
    private var loadID: UUID?
    private var loadTask: Task<SuppliedAnimationClip, Error>?
    private var playbackClock: UUID?
    private var sampleEpoch: UUID?
    private var worker: Task<Mesh, Error>?
    private var pendingPosition: (playback: AnimationPCMPlaybackPosition, groundOffset: SIMD2<Double>)?
    private var failedSampleIndex: Int?
    private var presentedFrame: SuppliedAnimationFrame?

    init(
        skin: @escaping @Sendable (GeneratedRig, [[Double]]) async throws -> Mesh = {
            try $0.referenceSkinnedMesh(modelFromJoint: $1)
        }
    ) {
        self.skin = skin
    }

    /// Install only the result of the current request, even when a cancelled producer returns.
    func load(
        source: SuppliedAnimationSource, currentSource: @MainActor () -> SuppliedAnimationSource?,
        using loader: @escaping @Sendable (SuppliedAnimationSource) async throws -> SuppliedAnimationClip
    ) async throws -> UUID? {
        guard !Task.isCancelled, currentSource() == source else { return nil }
        stop()
        let id = UUID()
        loadID = id
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await loader(source)
        }
        loadTask = task
        let result = await withTaskCancellationHandler {
            await task.result
        } onCancel: {
            task.cancel()
        }
        guard loadID == id else { return nil }
        loadTask = nil
        loadID = nil
        guard !Task.isCancelled, !task.isCancelled, currentSource() == source else { return nil }
        let clip = try result.get()
        guard clip.source == source else { throw SuppliedAnimationClipError.sourceMismatch }
        return install(clip)
    }

    func install(_ clip: SuppliedAnimationClip) -> UUID {
        stop()
        let lease = UUID()
        clipLease = lease
        playbackClock = lease
        self.clip = clip
        return lease
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        loadID = nil
        cancelPendingSample()
        clipLease = nil
        playbackClock = nil
        clip = nil
        presentedFrame = nil
    }

    /// Pause clock-driven work while retaining the last displayed frame for scrubbing.
    /// A restarted scheduler must use the returned clock token for both pose ticks and PCM reads.
    @discardableResult
    func setPlaybackPaused(_ paused: Bool, lease: UUID, currentSource: SuppliedAnimationSource) -> UUID? {
        guard clipLease == lease, clip?.source == currentSource else { return nil }
        if paused {
            if playbackClock != nil { cancelPendingSample() }
            playbackClock = nil
        } else if playbackClock == nil {
            playbackClock = UUID()
        }
        return playbackClock
    }

    private func cancelPendingSample() {
        worker?.cancel()
        worker = nil
        sampleEpoch = nil
        pendingPosition = nil
        failedSampleIndex = nil
    }

    func frame(lease: UUID, currentSource: SuppliedAnimationSource) -> SuppliedAnimationFrame? {
        guard clipLease == lease, clip?.source == currentSource else { return nil }
        return presentedFrame
    }

    func previewSampleCount(lease: UUID, currentSource: SuppliedAnimationSource) -> Int? {
        guard clipLease == lease, let clip, clip.source == currentSource else { return nil }
        return clip.timeline.previewSampleCount
    }

    func previewSampleTime(at index: Int, lease: UUID, currentSource: SuppliedAnimationSource) throws -> Double? {
        guard clipLease == lease, let clip, clip.source == currentSource else { return nil }
        return try clip.timeline.previewSampleTime(at: index)
    }

    func hasAudio(lease: UUID, currentSource: SuppliedAnimationSource) -> Bool {
        clipLease == lease && clip?.source == currentSource && clip?.pcm != nil
    }

    /// Capture the whole clip independently of its playback clock and seek position.
    func captureWav(lease: UUID, currentSource: SuppliedAnimationSource) -> SuppliedAnimationWavCapture? {
        guard clipLease == lease, let clip, clip.source == currentSource, let pcm = clip.pcm else { return nil }
        return SuppliedAnimationWavCapture(lease: lease, source: currentSource, samples: pcm.wavSamples)
    }

    /// Recheck after any save-panel or encoding suspension, immediately before publication.
    func canPublishWav(_ capture: SuppliedAnimationWavCapture, currentSource: SuppliedAnimationSource) -> Bool {
        clipLease == capture.lease && clip?.source == currentSource && capture.source == currentSource
    }

    /// Return one bounded PCM device buffer for the current clip. The scheduler must discard
    /// previously scheduled slices when its clip or source lease retires.
    func audioSamples(
        atRenderedFrame frame: UInt64, maximumFrames: Int, lease: UUID, currentSource: SuppliedAnimationSource,
        resumingAtSample: Int? = nil, clock: UUID? = nil
    ) throws -> ArraySlice<Int16>? {
        guard !Task.isCancelled, playbackClock == (clock ?? lease), clipLease == lease, let clip,
            clip.source == currentSource
        else { return nil }
        return try clip.pcm?.scheduledSamples(
            atRenderedFrame: frame, maximumFrames: maximumFrames, resumingAtSample: resumingAtSample)
    }

    /// Same-sample ticks update the presentation time without starting skinning again.
    /// A failed sample can be retried explicitly or after a request for a different sample.
    @discardableResult
    func sample(
        _ sample: SuppliedAnimationSample, lease: UUID, retryFailedSample: Bool = false, clock: UUID? = nil,
        currentSource: @MainActor () -> SuppliedAnimationSource?
    ) async -> Result<SuppliedAnimationFrame, Error>? {
        guard !Task.isCancelled, clipLease == lease, let clip, currentSource() == clip.source else { return nil }
        if playbackClock != (clock ?? lease) {
            guard case .scrub = sample else { return nil }
        }
        let playbackPosition: AnimationPCMPlaybackPosition
        let groundTime: Double
        do {
            switch sample {
            case .elapsed(let time):
                playbackPosition = try AnimationPCMPlaybackPosition(
                    pose: clip.timeline.position(at: time), pcmFrameOffset: nil)
                groundTime = clip.timeline.loops ? time : playbackPosition.pose.seconds
            case .resumedElapsed(let time, let sample):
                let resumed = try clip.timeline.resume(fromSample: sample, elapsed: time)
                playbackPosition = AnimationPCMPlaybackPosition(pose: resumed.pose, pcmFrameOffset: nil)
                groundTime = resumed.groundTime
            case .scrub(let time):
                playbackPosition =
                    try clip.pcm?.seek(to: time)
                    ?? AnimationPCMPlaybackPosition(pose: clip.timeline.scrub(to: time), pcmFrameOffset: nil)
                groundTime = try clip.timeline.sampleTime(at: playbackPosition.pose.sampleIndex)
            case .renderedAudioFrame(let frame):
                guard let pcm = clip.pcm else { throw SuppliedAnimationClipError.missingAudio }
                let projected = try pcm.project(atRenderedFrame: frame)
                playbackPosition = projected.position
                groundTime = projected.groundTime
            case .resumedAudioFrame(let frame, let sample):
                guard let pcm = clip.pcm else { throw SuppliedAnimationClipError.missingAudio }
                let resumed = try pcm.resume(fromSample: sample, renderedFrames: frame)
                playbackPosition = resumed.position
                groundTime = resumed.groundTime
            }
        } catch {
            return .failure(error)
        }
        let groundOffset = clip.groundVelocity * groundTime
        guard groundOffset.x.isFinite, groundOffset.y.isFinite else {
            return .failure(SuppliedAnimationClipError.invalidGroundMotion)
        }
        let presentation = (playback: playbackPosition, groundOffset: groundOffset)
        let position = playbackPosition.pose
        if let worker, !worker.isCancelled {
            if pendingPosition?.playback.pose.sampleIndex == position.sampleIndex {
                pendingPosition = presentation
                return nil
            }
            // A later clock tick will catch up after this pose completes. An
            // explicit scrub can still supersede an in-flight pose immediately.
            guard case .scrub = sample else { return nil }
        }
        if let presentedFrame, presentedFrame.position.sampleIndex == position.sampleIndex {
            cancelPendingSample()
            let updated = SuppliedAnimationFrame(
                playbackPosition: playbackPosition, groundOffset: groundOffset, mesh: presentedFrame.mesh,
                lease: lease, restBounds: clip.restBounds)
            self.presentedFrame = updated
            return .success(updated)
        }
        if failedSampleIndex == position.sampleIndex, !retryFailedSample { return nil }

        worker?.cancel()
        failedSampleIndex = nil
        pendingPosition = presentation
        let epoch = UUID()
        sampleEpoch = epoch
        let skin = skin
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let mesh = try await skin(clip.rig, clip.pose(at: position.sampleIndex))
            try Task.checkCancellation()
            return mesh
        }
        worker = task
        let result = await withTaskCancellationHandler {
            await task.result
        } onCancel: {
            task.cancel()
        }
        guard sampleEpoch == epoch else { return nil }
        worker = nil
        let latestPosition = pendingPosition ?? presentation
        pendingPosition = nil
        guard !Task.isCancelled, !task.isCancelled, currentSource() == clip.source else { return nil }
        switch result {
        case .success(let mesh):
            let frame = SuppliedAnimationFrame(
                playbackPosition: latestPosition.playback, groundOffset: latestPosition.groundOffset, mesh: mesh,
                lease: lease, restBounds: clip.restBounds)
            presentedFrame = frame
            return .success(frame)
        case .failure(let error):
            if !(error is CancellationError) { failedSampleIndex = position.sampleIndex }
            return .failure(error)
        }
    }
}
