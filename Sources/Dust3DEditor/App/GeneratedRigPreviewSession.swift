import Dust3DEditorModel
import Dust3DKit
import Dust3DRendering
import Foundation
import Observation

/// One document window owns copied rest data and work independently of presentation.
@MainActor @Observable
final class GeneratedRigPreviewSession {
    enum Presentation: String, CaseIterable, Hashable {
        case model = "Model"
        case generatedRest = "Generated Rest"
    }

    let generation: GeneratedRigPreviewState
    let display: GeneratedRigDisplayState
    private(set) var request: GeneratedRigPreviewRequest?
    private(set) var presentation = Presentation.model
    private(set) var presentationRevision = UUID()
    private(set) var selection: GeneratedRigJointSelection?
    var isWireframe = false
    var showsModel = true { didSet { if oldValue != showsModel { invalidatePicking() } } }
    var showsBones = true { didSet { if oldValue != showsBones { invalidatePicking() } } }
    private(set) var pickingRevision = UUID()
    private(set) var isPicking = false
    private(set) var pickingStatus: String?
    private var hitError: String?
    private(set) var showsWeights = true
    private var templateName = Data()
    private var appearance: RigTemplatePreviewAppearance?
    @ObservationIgnored private let readSnapshot: @MainActor () -> EditorSnapshot?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var displayTask: Task<Void, Never>?
    @ObservationIgnored private var pickingTask: Task<Void, Never>?
    @ObservationIgnored private var pickingJob = UUID()
    @ObservationIgnored private let picker:
        @Sendable (MeshPickingGeometry, MeshPickInput, Range<Int>?) async throws -> MeshPickResult
    @ObservationIgnored private var generationEpoch = UUID()
    @ObservationIgnored private var displayEpoch = UUID()
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var pendingTemplate: (GeneratedRigPreviewRequest, Data)?
    @ObservationIgnored lazy var cameraState = MeshCameraState(interactionAllowed: { [weak self] in
        self?.isReady == true
    })

    init(
        generation: GeneratedRigPreviewState, display: GeneratedRigDisplayState,
        readSnapshot: @escaping @MainActor () -> EditorSnapshot?,
        picker: @escaping @Sendable (MeshPickingGeometry, MeshPickInput, Range<Int>?) async throws -> MeshPickResult = {
            geometry, input, range in try geometry.pick(input, drawRange: range)
        }
    ) {
        self.generation = generation
        self.display = display
        self.readSnapshot = readSnapshot
        self.picker = picker
    }

    #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
        convenience init(readSnapshot: @escaping @MainActor () -> EditorSnapshot?) {
            self.init(
                generation: GeneratedRigPreviewState(), display: GeneratedRigDisplayState(), readSnapshot: readSnapshot)
        }
    #endif

    var currentRig: GeneratedRig? {
        guard sourceIsCurrent, generation.request == request else { return nil }
        return generation.rig
    }
    var currentRevision: UUID? { currentRig == nil ? nil : generation.revision }
    var selectedIndex: Int? {
        guard let rig = currentRig, let revision = currentRevision else { return nil }
        let name = String(decoding: templateName, as: UTF8.self)
        if let selection { return selection.resolvedIndex(in: rig, revision: revision, incomingName: name) }
        return rig.joints.firstIndex { $0.name.utf8.elementsEqual(templateName) }
    }
    var selectedName: String {
        guard let rig = currentRig, let index = selectedIndex else { return "" }
        return rig.joints[index].name
    }
    var desiredDisplay: GeneratedRigDisplayRequest? {
        guard let revision = currentRevision, let appearance else { return nil }
        return GeneratedRigDisplayRequest(
            rigRevision: revision, selectedBoneName: selectedName, appearance: appearance, showsWeights: showsWeights)
    }
    var isReady: Bool {
        guard let desired = desiredDisplay else { return false }
        return display.acceptedRequest == desired && display.mesh != nil && !display.isLoading && display.error == nil
    }
    /// Draw spans reference the complete accepted stream, never filtered geometry.
    var drawRange: Range<Int>? {
        guard isReady, let mesh = display.mesh, let boundary = display.skeletonVertexCount else { return 0..<0 }
        if showsModel && showsBones { return nil }
        if !showsModel && !showsBones { return 0..<0 }
        return showsBones ? 0..<boundary : boundary..<mesh.vertices.count
    }
    var canMoveCamera: Bool {
        isReady && (drawRange.map { !$0.isEmpty } ?? true)
    }
    func setShowsWeights(_ value: Bool) {
        guard !stopped, showsWeights != value else { return }
        showsWeights = value
        prepareDisplay()
    }

    var canPick: Bool {
        isReady && showsBones && display.pickingGeometry?.hasBones == true
    }
    var pickingError: String? {
        guard sourceIsCurrent, display.acceptedRequest == desiredDisplay else { return nil }
        return hitError ?? display.pickingError
    }

    func pick(_ input: MeshPickInput, lease: UUID) {
        guard !Task.isCancelled, pickingRevision == lease, canPick, let geometry = display.pickingGeometry else {
            return
        }
        pickingTask?.cancel()
        let job = UUID()
        pickingJob = job
        let cameraInput = cameraState.inputRevision
        let range = drawRange
        let picker = picker
        isPicking = true
        hitError = nil
        pickingStatus = nil
        pickingTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let result = try await picker(geometry, input, range)
                try Task.checkCancellation()
                return result
            }
            let result: Result<MeshPickResult, Error>
            do {
                result = .success(
                    try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    })
            } catch { result = .failure(error) }
            self?.finishPicking(result, job: job, lease: lease, cameraInput: cameraInput)
        }
    }

    private func finishPicking(_ result: Result<MeshPickResult, Error>, job: UUID, lease: UUID, cameraInput: UUID) {
        guard pickingJob == job else { return }
        pickingTask = nil
        isPicking = false
        guard !Task.isCancelled, pickingRevision == lease, canPick, cameraState.inputRevision == cameraInput else {
            return
        }
        switch result {
        case .success(.bone(let index)):
            guard let revision = currentRevision else { return }
            selectJoint(index, revision: revision)
        case .success(.body): pickingStatus = "Model surface at this point. Hide Model to select bones behind it."
        case .success(.miss): pickingStatus = "No bone at this point; selection is unchanged."
        case .failure(is CancellationError): break
        case .failure(let cause): hitError = EditorStore.message(cause)
        }
    }

    private func invalidatePicking() {
        pickingRevision = UUID()
        pickingJob = UUID()
        pickingTask?.cancel()
        pickingTask = nil
        isPicking = false
        pickingStatus = nil
        hitError = nil
    }

    private var sourceIsCurrent: Bool {
        guard !stopped, let request, let snapshot = readSnapshot() else { return false }
        // New inputs are byte-validated in update. Actor-owned snapshots advance
        // documentRevision for edits/Undo, so pointer input need not encode archives.
        return request.matchesVersion(snapshot)
    }

    func update(
        request: GeneratedRigPreviewRequest, selectedBoneName: String?, appearance: RigTemplatePreviewAppearance
    ) {
        guard !stopped, !Task.isCancelled, let snapshot = readSnapshot() else { return }
        guard self.request == request ? request.matchesVersion(snapshot) : request.matches(snapshot) else { return }
        let changed = self.request != request
        self.appearance = appearance
        if changed {
            let sameTemplate =
                self.request?.documentIdentity == request.documentIdentity
                && self.request?.sourceType.map { Data($0.utf8) } == request.sourceType.map { Data($0.utf8) }
            if let pendingTemplate, pendingTemplate.0 == request {
                templateName = pendingTemplate.1
            } else if !sameTemplate {
                templateName = Data((selectedBoneName ?? "").utf8)
            }
            self.request = request
            pendingTemplate = nil
            selection = nil
            beginGeneration()
        } else {
            // A remounted view may still carry an older template value. Only
            // explicit template actions can change selection after source setup.
            prepareDisplay()
        }
    }

    func setTemplateSelection(_ name: String, request: GeneratedRigPreviewRequest) {
        guard !stopped, !Task.isCancelled, let snapshot = readSnapshot(), request.matchesVersion(snapshot) else {
            return
        }
        invalidatePicking()
        let bytes = Data(name.utf8)
        if self.request != request {
            pendingTemplate = (request, bytes)
            return
        }
        guard bytes != templateName || selection != nil else { return }
        templateName = bytes
        selection = nil
        prepareDisplay()
    }

    func setPresentation(_ presentation: Presentation) {
        guard !stopped, self.presentation != presentation else { return }
        self.presentation = presentation
        presentationRevision = UUID()
        invalidatePicking()
    }

    func selectJoint(_ index: Int?, revision: UUID) {
        guard canInteract(revision), let rig = currentRig, index.map({ rig.joints.indices.contains($0) }) ?? true else {
            return
        }
        invalidatePicking()
        selection = GeneratedRigJointSelection(revision: revision, index: index)
        prepareDisplay()
    }
    func move(_ action: MeshCameraCommand.Action, revision: UUID?) {
        guard let revision, canInteract(revision), canMoveCamera else { return }
        invalidatePicking()
        cameraState.move(action)
    }
    func fit(revision: UUID?) {
        guard let revision, canInteract(revision), canMoveCamera else { return }
        invalidatePicking()
        cameraState.fit()
    }
    func allowsCameraInteraction(revision: UUID, presentationRevision: UUID) -> Bool {
        self.presentationRevision == presentationRevision && canInteract(revision) && canMoveCamera
    }

    private func canInteract(_ revision: UUID) -> Bool {
        guard sourceIsCurrent, let request else { return false }
        return generation.isCurrent(request: request, revision: revision)
    }

    func retryGeneration(request: GeneratedRigPreviewRequest, revision: UUID?) {
        guard sourceIsCurrent, self.request == request, generation.revision == revision else { return }
        beginGeneration()
    }
    func retryDisplay(request: GeneratedRigDisplayRequest?, revision: UUID?) {
        guard sourceIsCurrent, let request, desiredDisplay == request,
            display.request == request, display.revision == revision
        else { return }
        prepareDisplay(force: true)
    }

    private func beginGeneration() {
        guard let request else { return }
        invalidatePicking()
        generationTask?.cancel()
        displayTask?.cancel()
        displayEpoch = UUID()
        display.stop()
        let epoch = UUID()
        generationEpoch = epoch
        cameraState.fit()
        generationTask = Task { [weak self] in
            guard let self else { return }
            await self.generation.load(request)
            guard !Task.isCancelled, self.generationEpoch == epoch, self.sourceIsCurrent else { return }
            self.generationTask = nil
            self.prepareDisplay()
        }
    }
    private func prepareDisplay(force: Bool = false) {
        guard let desired = desiredDisplay, let rig = currentRig else { return }
        if !force, display.request == desired,
            display.isLoading || display.acceptedRequest == desired || display.error != nil
        {
            return
        }
        invalidatePicking()
        displayTask?.cancel()
        let epoch = UUID()
        displayEpoch = epoch
        displayTask = Task { [weak self] in
            guard let self else { return }
            await self.display.load(desired, rig: rig)
            guard self.displayEpoch == epoch else { return }
            self.displayTask = nil
        }
    }
    func stop() {
        stopped = true
        invalidatePicking()
        generationEpoch = UUID()
        displayEpoch = UUID()
        generationTask?.cancel()
        displayTask?.cancel()
        generationTask = nil
        displayTask = nil
        pendingTemplate = nil
        request = nil
        selection = nil
        generation.stop()
        display.stop()
    }
}
