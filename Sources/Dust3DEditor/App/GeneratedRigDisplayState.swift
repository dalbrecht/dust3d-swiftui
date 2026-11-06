import Dust3DKit
import Foundation
import Observation

/// Display inputs are independent of the document-generation request and camera.
/// Exact UTF-8 identity keeps canonically equivalent source names distinct.
struct GeneratedRigDisplayRequest: Sendable, Hashable {
    let rigRevision: UUID
    let selectedBoneName: String
    let appearance: RigTemplatePreviewAppearance

    static func == (left: Self, right: Self) -> Bool {
        left.rigRevision == right.rigRevision
            && left.selectedBoneName.utf8.elementsEqual(right.selectedBoneName.utf8)
            && left.appearance == right.appearance
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rigRevision)
        hasher.combine(Data(selectedBoneName.utf8))
        hasher.combine(appearance)
    }
}

private struct GeneratedRigDisplayPrepared: Sendable {
    let mesh: Mesh
    let weightSummary: GeneratedRigWeightSummary?
}

/// Recolors copied rest data without regenerating a rig or evaluating a pose.
/// Retained geometry keeps the viewport/camera alive during replacement. Views
/// must hide it unless acceptedRequest matches their current display request.
@MainActor @Observable
final class GeneratedRigDisplayState {
    private(set) var request: GeneratedRigDisplayRequest?
    private(set) var acceptedRequest: GeneratedRigDisplayRequest?
    private(set) var revision: UUID?
    private(set) var mesh: Mesh?
    private(set) var weightSummary: GeneratedRigWeightSummary?
    private(set) var meshRigRevision: UUID?
    private(set) var meshRevision = 0
    private(set) var error: String?
    private(set) var isLoading = false
    @ObservationIgnored private var worker: Task<GeneratedRigDisplayPrepared, Error>?
    @ObservationIgnored private let builder: @Sendable (GeneratedRig, GeneratedRigDisplayRequest) async throws -> Mesh

    init(builder: @escaping @Sendable (GeneratedRig, GeneratedRigDisplayRequest) async throws -> Mesh) {
        self.builder = builder
    }

    #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
        convenience init() {
            self.init { rig, request in
                let skeleton = try rig.skeletonMesh(selectedBoneName: request.selectedBoneName)
                return try rig.previewMesh(
                    skeleton: skeleton, selectedBoneName: request.selectedBoneName,
                    boneColor: request.appearance.boneColor,
                    selectedBoneColor: request.appearance.selectedBoneColor, ringColor: request.appearance.ringColor)
            }
        }
    #endif

    func load(_ request: GeneratedRigDisplayRequest, rig: GeneratedRig) async {
        // A cancelled obsolete view task must not disrupt newer display work.
        guard !Task.isCancelled else { return }
        worker?.cancel()
        let stamp = UUID()
        revision = stamp
        self.request = request
        acceptedRequest = nil
        error = nil
        isLoading = true
        let builder = builder
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let mesh = try await builder(rig, request)
            try Task.checkCancellation()
            let summary = try rig.weightSummary(selectedBoneName: request.selectedBoneName)
            try Task.checkCancellation()
            return GeneratedRigDisplayPrepared(mesh: mesh, weightSummary: summary)
        }
        worker = task
        let result: Result<GeneratedRigDisplayPrepared, Error>
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
            mesh = value.mesh
            weightSummary = value.weightSummary
            meshRigRevision = request.rigRevision
            meshRevision += 1
            acceptedRequest = request
        case .failure(is CancellationError):
            revision = nil
            self.request = nil
        case .failure(let cause): error = EditorStore.message(cause)
        }
    }

    func recordRenderFailure(_ cause: String, revision: UUID) {
        guard self.revision == revision, mesh != nil, acceptedRequest == request, !isLoading else { return }
        error = cause
    }

    func stop() {
        worker?.cancel()
        worker = nil
        request = nil
        acceptedRequest = nil
        revision = nil
        mesh = nil
        weightSummary = nil
        meshRigRevision = nil
        error = nil
        isLoading = false
    }
}
