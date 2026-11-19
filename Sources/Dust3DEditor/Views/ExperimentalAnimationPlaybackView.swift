import Accessibility
import AppKit
import SwiftUI

struct ExperimentalAnimationPlaybackView: View {
    let request: EditorStore.AnimationPlaybackRequest
    let isCurrent: @MainActor () -> Bool
    let loader: @Sendable (SuppliedAnimationSource, Bool) async throws -> SuppliedAnimationClip

    var wavDestinations: EditorGeometryExportDestinationService? = nil
    var onPreviewErrorAnnouncement: @MainActor (String) -> Void = {
        AccessibilityNotification.Announcement($0).post()
    }
    var previewAnnouncementIsActive: @MainActor (NSView) -> Bool = {
        NSApp.isActive && $0.window?.isKeyWindow == true
    }

    @State private var preview = SuppliedAnimationPreview()
    @State private var rigRevision = UUID()
    @State private var lease: UUID?
    @State private var clock: UUID?
    @State private var frame: SuppliedAnimationFrame?
    @State private var frameCount = 0
    @State private var sliderFrame = 0
    @State private var scrubID = UUID()
    @State private var resumeFrame = 0
    @State private var elapsedBeforePlay = 0.0
    @State private var elapsed = 0.0
    @State private var errorMessage: String?
    @State private var retry = 0
    @State private var sound = false
    @State private var isWireframe = false
    #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
        @State private var audioOutput: ExperimentalAnimationAudioOutput?
        @State private var audioFrames: UInt64 = 0
        @State private var wavExport: Task<Void, Never>?
        @State private var wavStatus: String?
    #endif

    private var source: SuppliedAnimationSource {
        SuppliedAnimationSource(playbackRequest: request, rigRevision: rigRevision)
    }

    private func currentSource() -> SuppliedAnimationSource? {
        isCurrent() ? source : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Animation Preview").font(.headline)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Retry Preview") { retry += 1 }
            } else if lease == nil {
                ProgressView("Preparing preview…").controlSize(.small)
            }
            if let frame {
                frame.viewport(isWireframe: isWireframe, cameraReset: 0) { errorMessage = $0 }
                    .frame(minHeight: 160)
                    .accessibilityLabel("Animation preview")
                Toggle("Wireframe", isOn: $isWireframe)
            }
            #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
                Toggle(
                    "Play Sound",
                    isOn: Binding(
                        get: { sound },
                        set: { enabled in
                            pause()
                            sound = enabled
                            retry += 1
                        }))
                if let wavDestinations {
                    Button("Export WAV…") { saveWav(using: wavDestinations) }
                        .disabled(wavExport != nil || wavCapture == nil)
                    if let wavStatus {
                        Text(wavStatus).font(.caption).textSelection(.enabled)
                    }
                }
            #endif
            if frameCount > 0 {
                HStack {
                    Button(clock == nil ? "Play" : "Pause", action: togglePlayback)
                    if frameCount > 1 {
                        Slider(
                            value: Binding(
                                get: { Double(sliderFrame) },
                                set: { value in
                                    pause()
                                    sliderFrame = Int(value)
                                    resumeFrame = sliderFrame
                                    elapsed = 0
                                    #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
                                        audioFrames = 0
                                    #endif
                                    scrubID = UUID()
                                }),
                            in: 0...Double(frameCount - 1), step: 1
                        ) { Text("Animation frame") }
                        .accessibilityValue("Frame \(sliderFrame + 1) of \(frameCount)")
                    }
                }
            }
        }
        .background(
            AnimationPreviewErrorAnnouncement(
                message: errorMessage, isCurrent: isCurrent,
                isActive: previewAnnouncementIsActive, announce: onPreviewErrorAnnouncement)
        )
        .task(id: retry) { await load() }
        .task(id: scrubID) { await scrub() }
        .task(id: clock) {
            if let clock { await play(clock: clock) }
        }
        .onDisappear {
            #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
                wavExport?.cancel()
            #endif
            pause()
            preview.stop()
        }
    }

    #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
        private var wavCapture: SuppliedAnimationWavCapture? {
            guard let lease, let current = currentSource() else { return nil }
            return preview.captureWav(lease: lease, currentSource: current)
        }

        private func saveWav(using destinations: EditorGeometryExportDestinationService) {
            guard wavExport == nil, let capture = wavCapture else { return }
            let sourceURL = destinations.attachedDocument?.fileURL
            wavStatus = nil
            wavExport = Task {
                defer { wavExport = nil }
                do {
                    let saved = try await AnimationWavExport.save(
                        sourceURL: sourceURL,
                        choose: { try await destinations.chooseWavDestination() },
                        encode: {
                            let worker = Task.detached { try capture.encodeWav() }
                            return try await withTaskCancellationHandler {
                                try await worker.value
                            } onCancel: {
                                worker.cancel()
                            }
                        },
                        isCurrent: {
                            guard let current = currentSource(), destinations.attachedDocument?.fileURL == sourceURL
                            else { return false }
                            return preview.canPublishWav(capture, currentSource: current)
                        })
                    if saved { wavStatus = "Animation sound exported." }
                } catch is CancellationError {
                    return
                } catch {
                    if currentSource() != nil { wavStatus = error.localizedDescription }
                }
            }
        }
    #endif

    private func load() async {
        guard !Task.isCancelled, currentSource() != nil else { return }
        let requestedFrame = sliderFrame
        pause()
        lease = nil
        frame = nil
        frameCount = 0
        elapsed = 0
        #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
            audioFrames = 0
        #endif
        errorMessage = nil
        let includePCM = sound
        let loadClip = loader
        do {
            guard
                let loaded = try await preview.load(
                    source: source, currentSource: currentSource, using: { try await loadClip($0, includePCM) })
            else { return }
            lease = loaded
            preview.setPlaybackPaused(true, lease: loaded, currentSource: source)
            frameCount = preview.previewSampleCount(lease: loaded, currentSource: source) ?? 0
            sliderFrame = min(requestedFrame, max(frameCount - 1, 0))
            resumeFrame = sliderFrame
            await scrub()
        } catch is CancellationError {
            return
        } catch {
            if currentSource() != nil { errorMessage = error.localizedDescription }
        }
    }

    private func togglePlayback() {
        if clock != nil {
            pause()
        } else if let lease, let current = currentSource() {
            if frame?.position.isFinished == true {
                resumeFrame = 0
                elapsed = 0
                #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
                    audioFrames = 0
                #endif
            }
            elapsedBeforePlay = elapsed
            clock = preview.setPlaybackPaused(false, lease: lease, currentSource: current)
        }
    }

    private func pause() {
        #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
            audioOutput?.stop()
            audioOutput = nil
        #endif
        if let lease { preview.setPlaybackPaused(true, lease: lease, currentSource: source) }
        clock = nil
    }

    private func scrub() async {
        guard let lease, let current = currentSource() else { return }
        do {
            guard let time = try preview.previewSampleTime(at: sliderFrame, lease: lease, currentSource: current)
            else { return }
            publish(await preview.sample(.scrub(time), lease: lease, currentSource: currentSource))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func play(clock token: UUID) async {
        guard let lease else { return }
        #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
            if sound, let current = currentSource(), preview.hasAudio(lease: lease, currentSource: current) {
                await playAudio(lease: lease, clock: token)
                return
            }
        #endif
        let timer = ContinuousClock()
        let start = timer.now
        while !Task.isCancelled, clock == token, currentSource() != nil {
            let time = start.duration(to: timer.now).components
            elapsed = elapsedBeforePlay + Double(time.seconds) + Double(time.attoseconds) / 1e18
            let result = await preview.sample(
                .resumedElapsed(elapsed, fromSample: resumeFrame), lease: lease, clock: token,
                currentSource: currentSource)
            guard !Task.isCancelled, clock == token else { return }
            publish(result)
            if let frame { sliderFrame = frame.position.sampleIndex }
            if case .success(let displayed)? = result, displayed.position.isFinished {
                pause()
                return
            }
            do {
                try await timer.sleep(for: .milliseconds(16))
            } catch {
                return
            }
        }
    }

    #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
        private func playAudio(lease: UUID, clock token: UUID) async {
            guard !Task.isCancelled, clock == token, let selected = currentSource() else { return }
            let anchor = audioFrames
            let selectedFrame = resumeFrame
            do {
                let output = try ExperimentalAnimationAudioOutput { offset, maximum in
                    guard clock == token, currentSource() == selected else { return nil }
                    let (position, overflow) = anchor.addingReportingOverflow(offset)
                    guard !overflow else { throw ExperimentalAnimationAudioError.unavailable }
                    return try preview.audioSamples(
                        atRenderedFrame: position, maximumFrames: maximum, lease: lease, currentSource: selected,
                        resumingAtSample: selectedFrame, clock: token)
                }
                audioOutput = output
                var poseTask: Task<Void, Never>?
                defer {
                    poseTask?.cancel()
                    output.stop()
                    if audioOutput === output { audioOutput = nil }
                }
                try output.start()
                while !Task.isCancelled, clock == token, currentSource() == selected {
                    let (position, overflow) = anchor.addingReportingOverflow(try output.renderedFrames())
                    guard !overflow else { throw ExperimentalAnimationAudioError.unavailable }
                    audioFrames = position
                    // Keep refilling audio even while the current pose is being skinned.
                    if poseTask == nil {
                        poseTask = Task { @MainActor in
                            defer { poseTask = nil }
                            let result = await preview.sample(
                                .resumedAudioFrame(position, fromSample: selectedFrame), lease: lease, clock: token,
                                currentSource: currentSource)
                            guard !Task.isCancelled, clock == token else { return }
                            publish(result)
                            if let frame { sliderFrame = frame.position.sampleIndex }
                            if case .success(let displayed)? = result, displayed.position.isFinished { pause() }
                        }
                    }
                    try await Task.sleep(for: .milliseconds(16))
                }
            } catch is CancellationError {
                return
            } catch {
                guard clock == token, currentSource() == selected else { return }
                pause()
                errorMessage = error.localizedDescription
            }
        }
    #endif

    private func publish(_ result: Result<SuppliedAnimationFrame, Error>?) {
        guard !Task.isCancelled, currentSource() != nil, let result else { return }
        switch result {
        case .success(let displayed): frame = displayed
        case .failure(let error):
            pause()
            errorMessage = error.localizedDescription
        }
    }
}

private struct AnimationPreviewErrorAnnouncement: NSViewRepresentable {
    let message: String?
    let isCurrent: @MainActor () -> Bool
    let isActive: @MainActor (NSView) -> Bool
    let announce: @MainActor (String) -> Void

    func makeNSView(context: Context) -> ReferenceCompositionErrorAnnouncementAnchor {
        ReferenceCompositionErrorAnnouncementAnchor()
    }

    func updateNSView(_ view: ReferenceCompositionErrorAnnouncementAnchor, context: Context) {
        view.update(message: isCurrent() ? message : nil, isActive: isActive(view), announce: announce)
    }
}
