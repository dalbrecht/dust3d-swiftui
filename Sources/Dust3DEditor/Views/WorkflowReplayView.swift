import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct WorkflowReplayRequest: Identifiable {
    let id = UUID()
    let document: Dust3DDocument
}

struct WorkflowReplayView: View {
    let document: Dust3DDocument
    @State private var plan: WorkflowReplayPlan?
    @State private var failure: String?
    @State private var completedSteps = 0
    @State private var isPlaying = false
    @State private var plane: EditingPlane = .front

    var body: some View {
        Group {
            if let plan {
                VStack(alignment: .leading) {
                    Picker("View", selection: $plane) {
                        ForEach(EditingPlane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    replayCanvas(plan)
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

    private func replayCanvas(_ plan: WorkflowReplayPlan) -> some View {
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
