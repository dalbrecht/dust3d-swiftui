import Dust3DDocument
import Dust3DEditorModel
import Foundation
import Observation

private actor WorkflowReplayCheckpointPreparation {
    func prepare(plan: WorkflowReplayPlan, source: Dust3DDocument, step: Int) throws -> EditorFileDocument {
        try Task.checkCancellation()
        let frame = try plan.previewDocument(after: step, source: source)
        _ = try EditorState(document: frame)
        try Task.checkCancellation()
        return try EditorFileDocument(data: frame.encoded())
    }
}

@MainActor @Observable
final class WorkflowReplayCheckpoint {
    struct Context: Equatable {
        let sourceID: UUID
        let step: Int
        let isPlaying: Bool
        var interactionRevision = 0
    }

    typealias Prepare = @Sendable (WorkflowReplayPlan, Dust3DDocument, Int) async throws -> EditorFileDocument

    private let prepare: Prepare
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private(set) var errorMessage: String?
    var isOpening: Bool { task != nil }

    init() {
        let preparation = WorkflowReplayCheckpointPreparation()
        prepare = { plan, source, step in
            try await preparation.prepare(plan: plan, source: source, step: step)
        }
    }

    init(prepare: @escaping Prepare) {
        self.prepare = prepare
    }

    func canOpen(_ context: Context, totalSteps: Int) -> Bool {
        !isOpening && !context.isPlaying && context.step > 0 && context.step <= totalSteps
    }

    @discardableResult
    func open(
        plan: WorkflowReplayPlan, source: Dust3DDocument, context: Context,
        current: @escaping @MainActor () -> Context?, deliver: @escaping @MainActor (EditorFileDocument) -> Void
    ) -> Task<Void, Never>? {
        guard canOpen(context, totalSteps: plan.steps.count), current() == context else { return nil }
        let request = UUID()
        requestID = request
        errorMessage = nil
        let operation = Task { [weak self, prepare] in
            defer {
                if let self, self.requestID == request {
                    self.task = nil
                    self.requestID = nil
                }
            }
            do {
                let document = try await prepare(plan, source, context.step)
                try Task.checkCancellation()
                guard self?.requestID == request, current() == context else { return }
                deliver(document)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError), self?.requestID == request,
                    current() == context
                else { return }
                self?.errorMessage = EditorStore.message(error)
            }
        }
        task = operation
        return operation
    }

    func cancel() {
        task?.cancel()
        task = nil
        requestID = nil
        errorMessage = nil
    }
}
