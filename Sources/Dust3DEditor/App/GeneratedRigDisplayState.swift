import Dust3DKit
import Dust3DRendering
import Foundation
import Observation

/// Display inputs are independent of the document-generation request and camera.
/// Exact UTF-8 identity keeps canonically equivalent source names distinct.
struct GeneratedRigDisplayRequest: Sendable, Hashable {
    let rigRevision: UUID
    let selectedBoneName: String
    let appearance: RigTemplatePreviewAppearance
    let showsWeights: Bool

    init(
        rigRevision: UUID, selectedBoneName: String, appearance: RigTemplatePreviewAppearance, showsWeights: Bool = true
    ) {
        self.rigRevision = rigRevision
        self.selectedBoneName = selectedBoneName
        self.appearance = appearance
        self.showsWeights = showsWeights
    }

    static func == (left: Self, right: Self) -> Bool {
        left.rigRevision == right.rigRevision
            && left.selectedBoneName.utf8.elementsEqual(right.selectedBoneName.utf8)
            && left.appearance == right.appearance && left.showsWeights == right.showsWeights
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rigRevision)
        hasher.combine(Data(selectedBoneName.utf8))
        hasher.combine(appearance)
        hasher.combine(showsWeights)
    }
}

/// Optional copied ownership is a derived picking aid. Its failure cannot
/// discard an otherwise valid rest mesh or weight summary.
struct GeneratedRigDisplayGeometry: Sendable {
    let mesh: Mesh
    let skeletonTriangleOwners: [UInt32]?
    let pickingFailure: String?

    init(mesh: Mesh, skeletonTriangleOwners: [UInt32]? = nil, pickingFailure: String? = nil) {
        self.mesh = mesh
        self.skeletonTriangleOwners = skeletonTriangleOwners
        self.pickingFailure = pickingFailure
    }
}

private struct GeneratedRigDisplayPrepared: Sendable {
    let mesh: Mesh
    let weightSummary: GeneratedRigWeightSummary?
    let skeletonVertexCount: Int
    let pickingGeometry: MeshPickingGeometry?
    let pickingError: String?
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
    private(set) var skeletonVertexCount: Int?
    private(set) var pickingGeometry: MeshPickingGeometry?
    private(set) var pickingError: String?
    private(set) var meshRigRevision: UUID?
    private(set) var meshRevision = 0
    private(set) var error: String?
    private(set) var isLoading = false
    @ObservationIgnored private var worker: Task<GeneratedRigDisplayPrepared, Error>?
    @ObservationIgnored private let preparer:
        @Sendable (GeneratedRig, GeneratedRigDisplayRequest) async throws -> GeneratedRigDisplayGeometry

    init(builder: @escaping @Sendable (GeneratedRig, GeneratedRigDisplayRequest) async throws -> Mesh) {
        preparer = { rig, request in GeneratedRigDisplayGeometry(mesh: try await builder(rig, request)) }
    }

    private init(
        preparer:
            @escaping @Sendable (GeneratedRig, GeneratedRigDisplayRequest) async throws -> GeneratedRigDisplayGeometry
    ) {
        self.preparer = preparer
    }

    static func withPicking(
        _ preparer:
            @escaping @Sendable (GeneratedRig, GeneratedRigDisplayRequest) async throws -> GeneratedRigDisplayGeometry
    ) -> GeneratedRigDisplayState {
        GeneratedRigDisplayState(preparer: preparer)
    }

    #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
        convenience init() {
            self.init(preparer: { rig, request in
                let skeleton = try rig.skeletonMesh(selectedBoneName: request.selectedBoneName)
                let mesh = try rig.previewMesh(
                    skeleton: skeleton, selectedBoneName: request.selectedBoneName, showsWeights: request.showsWeights,
                    boneColor: request.appearance.boneColor,
                    selectedBoneColor: request.appearance.selectedBoneColor, ringColor: request.appearance.ringColor)
                do {
                    return GeneratedRigDisplayGeometry(
                        mesh: mesh, skeletonTriangleOwners: try skeleton?.triangleOwners() ?? [])
                } catch is CancellationError { throw CancellationError() } catch {
                    return GeneratedRigDisplayGeometry(mesh: mesh, pickingFailure: error.localizedDescription)
                }
            })
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
        let preparer = preparer
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let geometry = try await preparer(rig, request)
            let mesh = geometry.mesh
            try Task.checkCancellation()
            // The builder's contract is a skeleton prefix followed by every copied
            // body vertex. Retain the complete stream for one stable camera frame.
            guard mesh.vertices.count >= rig.mesh.vertices.count,
                mesh.vertices.count.isMultiple(of: 3), rig.mesh.vertices.count.isMultiple(of: 3)
            else { throw RigTemplateHierarchyError.invalidMetadata("invalid generated rest body boundary") }
            let skeletonVertexCount = mesh.vertices.count - rig.mesh.vertices.count
            let summary = try rig.weightSummary(selectedBoneName: request.selectedBoneName)
            var pickingGeometry: MeshPickingGeometry?
            var pickingError = geometry.pickingFailure
            if let owners = geometry.skeletonTriangleOwners, pickingError == nil {
                do {
                    guard owners.count == skeletonVertexCount / 3 else {
                        throw RigTemplateHierarchyError.invalidMetadata("invalid picking skeleton/body boundary")
                    }
                    pickingGeometry = try MeshPickingGeometry(
                        mesh: mesh, skeletonTriangleOwners: owners, jointCount: rig.joints.count)
                } catch is CancellationError { throw CancellationError() } catch {
                    pickingError = error.localizedDescription
                }
            }
            try Task.checkCancellation()
            return GeneratedRigDisplayPrepared(
                mesh: mesh, weightSummary: summary, skeletonVertexCount: skeletonVertexCount,
                pickingGeometry: pickingGeometry, pickingError: pickingError)
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
            skeletonVertexCount = value.skeletonVertexCount
            pickingGeometry = value.pickingGeometry
            pickingError = value.pickingError
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
        skeletonVertexCount = nil
        pickingGeometry = nil
        pickingError = nil
        meshRigRevision = nil
        error = nil
        isLoading = false
    }
}
