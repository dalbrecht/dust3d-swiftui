import Dust3DKit
import Foundation
import Observation

/// Surface-local rest data only. Never edits documents or evaluates a pose.
/// The view must hide results whose request no longer matches its current snapshot.
@MainActor @Observable
final class GeneratedRigPreviewState {
    private(set) var request: GeneratedRigPreviewRequest?
    private(set) var revision: UUID?
    private(set) var rig: GeneratedRig?
    private(set) var error: String?
    private(set) var isLoading = false
    @ObservationIgnored private var worker: Task<GeneratedRig?, Error>?
    @ObservationIgnored private let loader: @Sendable (GeneratedRigPreviewRequest) async throws -> GeneratedRig?

    init(loader: @escaping @Sendable (GeneratedRigPreviewRequest) async throws -> GeneratedRig?) {
        self.loader = loader
    }

    #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
        convenience init() {
            self.init { request in
                try await GeneratedRigService().load(
                    data: request.archive, sourceType: request.sourceType, headHasEyelids: request.headHasEyelids)
            }
        }
    #endif

    func load(_ request: GeneratedRigPreviewRequest) async {
        // An obsolete cancelled view task must not replace/cancel a newer surface load.
        guard !Task.isCancelled else { return }
        worker?.cancel()
        let stamp = UUID()
        revision = stamp
        self.request = request
        rig = nil
        error = nil
        isLoading = true
        let loader = loader
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try await loader(request)
            try Task.checkCancellation()
            return result
        }
        worker = task
        let result: Result<GeneratedRig?, Error>
        do {
            result = .success(
                try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                })
        } catch {
            result = .failure(error)
        }
        guard revision == stamp else { return }
        worker = nil
        isLoading = false
        guard !Task.isCancelled else {
            revision = nil
            self.request = nil
            return
        }
        switch result {
        case .success(let value): rig = value
        case .failure(is CancellationError):
            revision = nil
            self.request = nil
        case .failure(let cause): error = EditorStore.message(cause)
        }
    }

    /// Queued interactions belong to one successfully published source request.
    func isCurrent(request: GeneratedRigPreviewRequest, revision: UUID) -> Bool {
        self.request == request && self.revision == revision && rig != nil
    }

    func recordRenderFailure(_ cause: String, revision: UUID) {
        guard self.revision == revision, rig != nil, !isLoading else { return }
        error = cause
    }

    func stop() {
        worker?.cancel()
        worker = nil
        revision = nil
        request = nil
        rig = nil
        error = nil
        isLoading = false
    }
}
