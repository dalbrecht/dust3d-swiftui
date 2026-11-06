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
    private var templateName = Data()
    private var appearance: RigTemplatePreviewAppearance?
    @ObservationIgnored private let readSnapshot: @MainActor () -> EditorSnapshot?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var displayTask: Task<Void, Never>?
    @ObservationIgnored private var generationEpoch = UUID()
    @ObservationIgnored private var displayEpoch = UUID()
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var pendingTemplate: (GeneratedRigPreviewRequest, Data)?
    @ObservationIgnored lazy var cameraState = MeshCameraState(interactionAllowed: { [weak self] in
        self?.isReady == true
    })

    init(
        generation: GeneratedRigPreviewState, display: GeneratedRigDisplayState,
        readSnapshot: @escaping @MainActor () -> EditorSnapshot?
    ) {
        self.generation = generation
        self.display = display
        self.readSnapshot = readSnapshot
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
        return GeneratedRigDisplayRequest(rigRevision: revision, selectedBoneName: selectedName, appearance: appearance)
    }
    var isReady: Bool {
        guard let desired = desiredDisplay else { return false }
        return display.acceptedRequest == desired && display.mesh != nil && !display.isLoading && display.error == nil
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
    }

    func selectJoint(_ index: Int?, revision: UUID) {
        guard canInteract(revision), let rig = currentRig, index.map({ rig.joints.indices.contains($0) }) ?? true else {
            return
        }
        selection = GeneratedRigJointSelection(revision: revision, index: index)
        prepareDisplay()
    }
    func move(_ action: MeshCameraCommand.Action, revision: UUID?) {
        guard let revision, canInteract(revision), isReady else { return }
        cameraState.move(action)
    }
    func fit(revision: UUID?) {
        guard let revision, canInteract(revision), isReady else { return }
        cameraState.fit()
    }
    func allowsCameraInteraction(revision: UUID, presentationRevision: UUID) -> Bool {
        self.presentationRevision == presentationRevision && canInteract(revision) && isReady
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
