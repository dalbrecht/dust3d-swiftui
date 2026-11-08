import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Dust3DRendering
import SwiftUI

struct WorkflowReplayWindow: View {
    let requestID: UUID?
    let windows: WorkflowReplayWindows
    @State private var owner = UUID()

    var body: some View {
        ZStack {
            if let request = windows.request(requestID, owner: owner) {
                WorkflowReplayView(document: request.document, sourceID: request.id) {
                    windows.request(request.id, owner: owner) != nil
                }
            } else {
                ContentUnavailableView {
                    Label("No Replay", systemImage: "play.rectangle")
                } description: {
                    Text("Choose Replay Steps from a document window to start a new replay.")
                }
            }
        }
        .onAppear { windows.attach(requestID, owner: owner) }
        .onDisappear { windows.close(requestID, owner: owner) }
    }
}

private actor WorkflowReplayMeshLoader {
    private let previews = FilePreviewDocumentService()

    func load(plan: WorkflowReplayPlan, document: Dust3DDocument, step: Int) async throws -> FilePreviewDocument {
        try Task.checkCancellation()
        let frame = try plan.meshPreviewDocument(at: step, source: document)
        return try await previews.load(document: frame)
    }
}

enum WorkflowReplayPlaybackPhase: Equatable {
    case empty
    case ready
    case inProgress
    case complete

    init(completedSteps: Int, totalSteps: Int) {
        if totalSteps == 0 {
            self = .empty
        } else if completedSteps == 0 {
            self = .ready
        } else {
            self = completedSteps < totalSteps ? .inProgress : .complete
        }
    }
}

enum WorkflowReplayReferenceState {
    case loading
    case ready(CGImage, CanvasBounds)
    case unavailable(String)

    func blocksAdvance(hasReferenceStep: Bool, completedSteps: Int) -> Bool {
        guard hasReferenceStep, completedSteps == 0, case .loading = self else { return false }
        return true
    }
}

enum WorkflowReplayMeshStatus: Equatable {
    case updating
    case failed(String)
    case empty
    case ready

    init(requestedStep: Int, displayedStep: Int?, hasMesh: Bool, failure: String?) {
        if requestedStep != displayedStep {
            self = .updating
        } else if let failure {
            self = .failed(failure)
        } else {
            self = hasMesh ? .ready : .empty
        }
    }
}

struct WorkflowReplayView: View {
    private enum Presentation: String, CaseIterable {
        case front = "Front (X/Y)"
        case side = "Side (Z/Y)"
        case mesh = "3D Preview"
    }

    let document: Dust3DDocument
    let sourceID: UUID
    let isCurrentSource: @MainActor () -> Bool
    @Environment(\.newDocument) private var newDocument
    @State private var checkpoint = WorkflowReplayCheckpoint()
    @State private var checkpointRevision = 0
    @State private var plan: WorkflowReplayPlan?
    @State private var failure: String?
    @State private var completedSteps = 0
    @State private var isPlaying = false
    @State private var speed = Double(WorkflowReplaySpeed.initial)
    @State private var presentation: Presentation = .front
    @State private var meshLoader = WorkflowReplayMeshLoader()
    @State private var mesh: IndexedMesh?
    @State private var materials: MeshMaterialContent?
    @State private var meshStep: Int?
    @State private var meshFailure: String?
    @State private var referenceState = WorkflowReplayReferenceState.loading

    private var waitsForReference: Bool {
        referenceState.blocksAdvance(
            hasReferenceStep: plan?.steps.first == .referenceImage, completedSteps: completedSteps)
    }

    private var playbackInterval: Int? {
        isPlaying ? WorkflowReplaySpeed.intervalMilliseconds(for: Int(speed)) : nil
    }

    private var requestedMeshStep: Int? {
        presentation == .mesh ? plan?.meshStep(after: completedSteps) : nil
    }

    private var playbackPhase: WorkflowReplayPlaybackPhase? {
        plan.map { WorkflowReplayPlaybackPhase(completedSteps: completedSteps, totalSteps: $0.steps.count) }
    }

    private var checkpointContext: WorkflowReplayCheckpoint.Context {
        .init(sourceID: sourceID, step: completedSteps, isPlaying: isPlaying, interactionRevision: checkpointRevision)
    }

    var body: some View {
        Group {
            if let plan, playbackPhase == .empty {
                ContentUnavailableView {
                    Label("No Replay Steps", systemImage: "play.rectangle")
                } description: {
                    if let animationMetadataError = plan.animationMetadataError {
                        Text("Animation steps unavailable. \(animationMetadataError)")
                    } else {
                        Text("This document has no steps to replay.")
                    }
                }
            } else if let plan, let phase = playbackPhase {
                VStack(alignment: .leading) {
                    Picker("View", selection: $presentation) {
                        ForEach(Presentation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if presentation == .mesh {
                        meshPreview
                    } else {
                        replayCanvas(plan, plane: presentation == .front ? .front : .side)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step \(completedSteps) of \(plan.steps.count)")
                            .monospacedDigit()
                        if phase == .ready {
                            Text("Ready to Replay")
                        } else {
                            if phase == .complete { Text("Replay Complete") }
                            switch plan.steps[completedSteps - 1] {
                            case .referenceImage: Text("Set Reference Image")
                            case .property(let property): Text("Set \(property.title)").lineLimit(2)
                            case .createGroup(_, let name):
                                if name.isEmpty {
                                    Text("Create Group")
                                } else {
                                    Text("Create Group: \(name)").lineLimit(2)
                                }
                            case .movePart(_, let groupName):
                                if groupName.isEmpty {
                                    Text("Move Part into Group")
                                } else {
                                    Text("Move Part into \(groupName)").lineLimit(2)
                                }
                            case .restoreEdgeDirections: Text("Restore Edge Directions")
                            case .node: Text("Draw Node")
                            case .edge: Text("Connect Nodes")
                            case .addAnimation(_, let name): Text("Add Animation \(name)").lineLimit(2)
                            case .setRigType(let type): Text("Set Rig Type to \(type)")
                            case .assignBone(let name, _): Text("Assign Edges to \(name.rawValue)").lineLimit(2)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if let property = plan.appliedProperty(after: completedSteps) {
                        WorkflowReplayPropertyDetail(property: property)
                    }
                    if waitsForReference {
                        ProgressView("Preparing reference image…")
                    } else if plan.showsReferenceImage(after: completedSteps),
                        case .unavailable(let message) = referenceState
                    {
                        Text(message).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let animationMetadataError = plan.animationMetadataError {
                        Text("Animation steps unavailable. \(animationMetadataError)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Reset") {
                            retireCheckpoint()
                            isPlaying = false
                            completedSteps = 0
                        }
                        .disabled(phase == .ready)
                        Button(isPlaying ? "Pause" : "Play") {
                            retireCheckpoint()
                            isPlaying.toggle()
                        }
                        .disabled(phase == .complete)
                        Button("Next Step") { advance(plan) }
                            .disabled(phase == .complete || isPlaying || waitsForReference)
                            .keyboardShortcut(.rightArrow, modifiers: .option)
                    }
                    let context = checkpointContext
                    HStack {
                        Button("Open Step as New Document") {
                            checkpoint.open(
                                plan: plan, source: document, context: context,
                                current: { isCurrentSource() ? checkpointContext : nil },
                                deliver: { file in newDocument(file) })
                        }
                        .disabled(!checkpoint.canOpen(context, totalSteps: plan.steps.count))
                        if checkpoint.isOpening {
                            ProgressView("Preparing editable copy…").controlSize(.small)
                            Button("Cancel Opening") { retireCheckpoint() }
                        }
                    }
                    if let error = checkpoint.errorMessage {
                        Text("Could not open replay step. \(error)").foregroundStyle(.secondary)
                    }
                    let seconds = Double(WorkflowReplaySpeed.intervalMilliseconds(for: Int(speed))) / 1000
                    Slider(
                        value: $speed,
                        in: Double(WorkflowReplaySpeed.range.lowerBound)...Double(WorkflowReplaySpeed.range.upperBound),
                        step: 1
                    ) {
                        Text("Playback Speed")
                    } minimumValueLabel: {
                        Text("Slower")
                    } maximumValueLabel: {
                        Text("Faster")
                    }
                    .accessibilityValue(
                        Text("\(seconds, format: .number.precision(.fractionLength(2))) seconds per step"))
                }
                .padding()
            } else if let failure {
                ContentUnavailableView {
                    Label("Replay Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                }
            } else {
                ProgressView("Preparing replay…")
            }
        }
        .task {
            do {
                let captured = document
                let prepared = try await Task.detached { try WorkflowReplayPlan(document: captured) }.value
                guard !Task.isCancelled else { return }
                plan = prepared
            } catch {
                guard !Task.isCancelled else { return }
                failure = EditorStore.message(error)
            }
        }
        .task(id: plan?.steps.first == .referenceImage) {
            guard let plan, plan.steps.first == .referenceImage else { return }
            do {
                let result = try await ReferenceImageService().preview(document: document)
                guard !Task.isCancelled else { return }
                guard let image = result.image else {
                    referenceState = .unavailable(String(localized: "The reference image is unavailable."))
                    return
                }
                let bounds = plan.bounds(referenceImageAspectRatio: Double(image.width) / Double(image.height))
                referenceState = .ready(image, bounds)
            } catch {
                guard !Task.isCancelled else { return }
                referenceState = .unavailable(EditorStore.message(error))
            }
        }
        .task(id: requestedMeshStep) {
            guard let step = requestedMeshStep, let plan else { return }
            meshFailure = nil
            if step == 0 {
                mesh = nil
                materials = nil
                meshStep = 0
                return
            }
            do {
                let loaded = try await meshLoader.load(plan: plan, document: document, step: step)
                guard !Task.isCancelled, requestedMeshStep == step else { return }
                mesh = loaded.mesh
                materials = loaded.materials
                meshStep = step
                meshFailure = loaded.materialError.map(EditorStore.message)
            } catch {
                guard !Task.isCancelled, requestedMeshStep == step else { return }
                mesh = nil
                materials = nil
                meshStep = step
                meshFailure = EditorStore.message(error)
            }
        }
        .onDisappear { retireCheckpoint() }
        .task(id: playbackInterval) {
            guard let interval = playbackInterval, let plan else { return }
            while !Task.isCancelled, completedSteps < plan.steps.count {
                do { try await Task.sleep(for: .milliseconds(interval)) } catch { return }
                guard !Task.isCancelled else { return }
                if let requestedMeshStep, meshStep != requestedMeshStep { continue }
                advance(plan)
            }
        }
    }

    private func retireCheckpoint() {
        checkpointRevision += 1
        checkpoint.cancel()
    }

    private func advance(_ plan: WorkflowReplayPlan) {
        guard !waitsForReference else { return }
        retireCheckpoint()
        completedSteps = min(completedSteps + 1, plan.steps.count)
        if completedSteps == plan.steps.count { isPlaying = false }
    }

    private var meshPreview: some View {
        let status = WorkflowReplayMeshStatus(
            requestedStep: requestedMeshStep ?? 0, displayedStep: meshStep, hasMesh: mesh != nil, failure: meshFailure)
        return ZStack(alignment: .bottom) {
            if let mesh, let meshStep {
                MeshViewport(
                    mesh: mesh, isWireframe: false, cameraReset: 0, meshRevision: meshStep,
                    materials: materials,
                    onMaterialError: { message in
                        if requestedMeshStep == meshStep { meshFailure = message }
                    }
                ) { message in
                    if requestedMeshStep == meshStep { meshFailure = message }
                }
                .opacity(status == .updating ? 0.35 : 1)
                .allowsHitTesting(status != .updating)
                .accessibilityHidden(status == .updating)
                .accessibilityLabel("Reconstructed 3D mesh")
            }
            switch status {
            case .updating:
                ProgressView("Updating 3D preview…").padding(8).background(.regularMaterial)
            case .failed(let message):
                Text(message).padding(8).background(.regularMaterial)
            case .empty:
                Text("No geometry at this step").padding(8)
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func replayCanvas(_ plan: WorkflowReplayPlan, plane: EditingPlane) -> some View {
        let frame = plan.frame(after: completedSteps)
        let nodes = Dictionary(uniqueKeysWithValues: frame.nodes.filter(\.isVisible).map { ($0.id, $0) })
        return Canvas { context, size in
            let reference: (image: CGImage, bounds: CanvasBounds)?
            if plan.showsReferenceImage(after: completedSteps), case .ready(let image, let bounds) = referenceState {
                reference = (image, bounds)
            } else {
                reference = nil
            }
            let projection = CanvasProjection(
                bounds: reference?.bounds ?? plan.bounds, plane: plane, width: size.width, height: size.height)
            if let referenceImage = reference?.image {
                let aspect = Double(referenceImage.width) / Double(referenceImage.height)
                let center = projection.point(for: .init(x: aspect / 2, y: 0.5, z: aspect / 2))
                let width = aspect * projection.scale
                let height = projection.scale
                var background = context
                background.opacity = 0.55
                background.draw(
                    Image(decorative: referenceImage, scale: 1),
                    in: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
            }
            func point(_ node: DocumentNode) -> CGPoint {
                let value = projection.point(for: node.value.position)
                return CGPoint(x: value.x, y: value.y)
            }
            for edge in frame.edges {
                guard let start = nodes[edge.fromID], let end = nodes[edge.toID] else { continue }
                var path = Path()
                path.move(to: point(start))
                path.addLine(to: point(end))
                context.stroke(path, with: .foreground, lineWidth: 1.5)
            }
            for node in frame.nodes where node.isVisible {
                let center = point(node)
                let radius = max(3, node.value.radius * projection.scale)
                let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: circle), with: .color(.accentColor), lineWidth: 2)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Reconstructed graph")
        .accessibilityValue("\(frame.nodes.count) nodes and \(frame.edges.count) edges")
    }
}

private struct WorkflowReplayPropertyDetail: View {
    let property: ReplayProperty

    private var ownerLabel: String {
        switch property.owner {
        case .node: "Node"
        case .part: "Part"
        case .component: "Component"
        case .animation: "Animation"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(ownerLabel, value: property.id)
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(property.fields, id: \.name) { field in
                    LabeledContent(field.name) {
                        if field.value.isEmpty {
                            Text("Empty").foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: field.value).textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
        }
        .frame(maxHeight: 100)
        .accessibilityLabel("Applied replay property")
    }
}
