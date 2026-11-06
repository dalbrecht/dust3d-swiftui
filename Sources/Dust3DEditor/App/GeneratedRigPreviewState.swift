import Dust3DKit
import Foundation
import Observation

private struct GeneratedRigPreviewPrepared: Sendable {
    let rig: GeneratedRig
    let hierarchy: GeneratedRigHierarchy?
    let hierarchyError: String?
}

/// Surface-local rest data only. Never edits documents or evaluates a pose.
/// The view must hide results whose request no longer matches its current snapshot.
@MainActor @Observable
final class GeneratedRigPreviewState {
    private(set) var request: GeneratedRigPreviewRequest?
    private(set) var revision: UUID?
    private(set) var rig: GeneratedRig?
    private(set) var hierarchy: GeneratedRigHierarchy?
    private(set) var hierarchyError: String?
    private(set) var error: String?
    private(set) var isLoading = false
    @ObservationIgnored private var worker: Task<GeneratedRigPreviewPrepared?, Error>?
    @ObservationIgnored private let loader: @Sendable (GeneratedRigPreviewRequest) async throws -> GeneratedRig?

    @ObservationIgnored private let hierarchyBuilder: @Sendable ([GeneratedRigJoint]) throws -> GeneratedRigHierarchy

    init(
        hierarchyBuilder: @escaping @Sendable ([GeneratedRigJoint]) throws -> GeneratedRigHierarchy = {
            try GeneratedRigHierarchy(joints: $0)
        }, loader: @escaping @Sendable (GeneratedRigPreviewRequest) async throws -> GeneratedRig?
    ) {
        self.loader = loader
        self.hierarchyBuilder = hierarchyBuilder
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
        hierarchy = nil
        hierarchyError = nil
        error = nil
        isLoading = true
        let loader = loader
        let hierarchyBuilder = hierarchyBuilder
        let task = Task.detached(priority: .userInitiated) { () async throws -> GeneratedRigPreviewPrepared? in
            try Task.checkCancellation()
            let result = try await loader(request)
            try Task.checkCancellation()
            guard let rig = result else { return nil }
            let hierarchy: GeneratedRigHierarchy?
            let hierarchyError: String?
            do {
                hierarchy = try hierarchyBuilder(rig.joints)
                hierarchyError = nil
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                hierarchy = nil
                hierarchyError = error.localizedDescription
            }
            try Task.checkCancellation()
            return GeneratedRigPreviewPrepared(rig: rig, hierarchy: hierarchy, hierarchyError: hierarchyError)
        }
        worker = task
        let result: Result<GeneratedRigPreviewPrepared?, Error>
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
        case .success(let value):
            rig = value?.rig
            hierarchy = value?.hierarchy
            hierarchyError = value?.hierarchyError
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
        hierarchy = nil
        hierarchyError = nil
        error = nil
        isLoading = false
    }
}
