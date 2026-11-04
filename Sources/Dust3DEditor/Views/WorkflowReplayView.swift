import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Dust3DRendering
import SwiftUI

struct WorkflowReplayRequest: Identifiable {
    let id = UUID()
    let document: Dust3DDocument
}

private actor WorkflowReplayMeshLoader {
    func load(plan: WorkflowReplayPlan, document: Dust3DDocument, step: Int) throws -> IndexedMesh? {
        try Task.checkCancellation()
        let frame = try plan.previewDocument(after: step, source: document)
        try Task.checkCancellation()
        return try MeshLoader.loadIndexedIfPresent(data: frame.encoded(), maximumPayloadBytes: 64 * 1024 * 1024)
    }
}

struct WorkflowReplayView: View {
    private enum Presentation: String, CaseIterable {
        case front = "Front (X/Y)"
        case side = "Side (Z/Y)"
        case mesh = "3D Preview"
    }

    let document: Dust3DDocument
    @State private var plan: WorkflowReplayPlan?
    @State private var failure: String?
    @State private var completedSteps = 0
    @State private var isPlaying = false
    @State private var presentation: Presentation = .front
    @State private var meshLoader = WorkflowReplayMeshLoader()
    @State private var mesh: IndexedMesh?
    @State private var meshStep: Int?
    @State private var meshFailure: String?

    private var requestedMeshStep: Int? {
        presentation == .mesh && plan != nil ? completedSteps : nil
    }

    var body: some View {
        Group {
            if let plan {
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
                    Text("Step \(completedSteps) of \(plan.steps.count)")
                        .monospacedDigit()
                    HStack {
                        Button("Reset") {
                            isPlaying = false
                            completedSteps = 0
                        }
                        .disabled(completedSteps == 0)
                        Button(isPlaying ? "Pause" : "Play") { isPlaying.toggle() }
                            .disabled(completedSteps == plan.steps.count)
                        Button("Next Step") { advance(plan) }
                            .disabled(completedSteps == plan.steps.count || isPlaying)
                            .keyboardShortcut(.rightArrow, modifiers: [])
                    }
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
        .task(id: requestedMeshStep) {
            guard let step = requestedMeshStep, let plan else { return }
            meshFailure = nil
            if step == 0 {
                mesh = nil
                meshStep = 0
                return
            }
            do {
                let loaded = try await meshLoader.load(plan: plan, document: document, step: step)
                guard !Task.isCancelled, requestedMeshStep == step else { return }
                mesh = loaded
                meshStep = step
            } catch {
                guard !Task.isCancelled, requestedMeshStep == step else { return }
                mesh = nil
                meshStep = step
                meshFailure = EditorStore.message(error)
            }
        }
        .task(id: isPlaying) {
            guard isPlaying, let plan else { return }
            while !Task.isCancelled, completedSteps < plan.steps.count {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard !Task.isCancelled else { return }
                advance(plan)
            }
        }
    }

    private func advance(_ plan: WorkflowReplayPlan) {
        completedSteps = min(completedSteps + 1, plan.steps.count)
        if completedSteps == plan.steps.count { isPlaying = false }
    }

    private var meshPreview: some View {
        ZStack(alignment: .bottom) {
            if let mesh, let meshStep {
                MeshViewport(mesh: mesh, isWireframe: false, cameraReset: 0, meshRevision: meshStep, materials: nil) {
                    meshFailure = $0
                }
                .accessibilityLabel("Reconstructed 3D mesh")
            }
            if let meshFailure {
                Text(meshFailure).padding(8).background(.regularMaterial)
            } else if meshStep != completedSteps {
                ProgressView("Updating 3D preview…").padding(8).background(.regularMaterial)
            } else if mesh == nil {
                Text("No geometry at this step").padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func replayCanvas(_ plan: WorkflowReplayPlan, plane: EditingPlane) -> some View {
        let frame = plan.frame(after: completedSteps)
        let nodes = Dictionary(uniqueKeysWithValues: frame.nodes.filter(\.isVisible).map { ($0.id, $0) })
        return Canvas { context, size in
            let projection = CanvasProjection(bounds: plan.bounds, plane: plane, width: size.width, height: size.height)
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
