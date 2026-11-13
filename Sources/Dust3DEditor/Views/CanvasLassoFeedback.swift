import Dust3DEditorModel
import Foundation
import Observation

struct CanvasLassoInteraction {
    let plan: CanvasLassoPickPlan
    let isCurrent: @MainActor () -> Bool
    let commit: @MainActor (CanvasLasso, @escaping @MainActor (Bool) -> Void) -> Void
}

struct CanvasLassoSample {
    let path: CanvasLasso
    let interaction: CanvasLassoInteraction
}

/// Draw immediately and evaluate only the latest queued path while one hit test is running.
@MainActor @Observable final class CanvasLassoFeedback {
    private(set) var path: CanvasLasso?
    private(set) var picks: CanvasLassoPickPlan.Picks?
    private var settlementID: UUID?
    var isCommitting: Bool { settlementID != nil }
    @ObservationIgnored private var pending: CanvasLassoSample?
    @ObservationIgnored private var worker: Task<Void, Never>?

    func update(_ sample: CanvasLassoSample?) {
        guard let sample else {
            clear()
            return
        }
        path = sample.path
        picks = nil
        pending = sample
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while !Task.isCancelled, let sample = self?.takePending() {
                let plan = sample.interaction.plan
                let path = sample.path
                let computation = Task.detached(priority: .userInitiated) {
                    plan.preview(in: path)
                }
                let result = await withTaskCancellationHandler {
                    await computation.value
                } onCancel: {
                    computation.cancel()
                }
                guard !Task.isCancelled else { return }
                guard self?.pending == nil else { continue }
                guard sample.interaction.isCurrent() else {
                    self?.clear()
                    return
                }
                self?.picks = result
            }
            if !Task.isCancelled { self?.worker = nil }
        }
    }

    func finish(_ sample: CanvasLassoSample) {
        stopPreview()
        if path?.points != sample.path.points { picks = nil }
        path = nil
        let id = UUID()
        settlementID = id
        sample.interaction.commit(sample.path) { [weak self] _ in
            guard let self, self.settlementID == id else { return }
            self.clear()
        }
    }

    func clear() {
        stopPreview()
        settlementID = nil
        path = nil
        picks = nil
    }

    private func stopPreview() {
        worker?.cancel()
        worker = nil
        pending = nil
    }

    private func takePending() -> CanvasLassoSample? {
        defer { pending = nil }
        return pending
    }
}
