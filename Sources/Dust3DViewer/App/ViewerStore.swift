import Dust3DKit
import Foundation
import Observation

@MainActor
@Observable
final class ViewerStore {
    private(set) var mesh: IndexedMesh?
    private(set) var bakedMesh: MeshWithBakedTextures?
    private(set) var documentName = "Dust3D Viewer"
    private(set) var isLoading = false
    private(set) var isBakingMaterials = false
    private(set) var materialIssue: String?
    private(set) var meshRevision = 0
    private(set) var materialRevision = 0
    var errorMessage: String?
    private let service: any MeshFileSnapshotLoading
    private let materialBaker: any ArchiveTextureBaking
    private(set) var loadTask: Task<Void, Never>?
    private(set) var materialTask: Task<Void, Never>?
    private var archiveData: Data?
    private var revision = 0
    private var materialRequestID = UUID()

    init(
        service: any MeshFileSnapshotLoading = MeshFileService(),
        materialBaker: any ArchiveTextureBaking = ArchiveTextureBakingService()
    ) {
        self.service = service
        self.materialBaker = materialBaker
    }

    func open(_ url: URL) {
        loadTask?.cancel()
        clearMaterials()
        revision += 1
        let requestedRevision = revision
        isLoading = true
        errorMessage = nil
        loadTask = Task { [weak self, service] in
            do {
                let loaded = try await service.loadIndexedSnapshot(url: url)
                try Task.checkCancellation()
                guard let self, self.revision == requestedRevision else { return }
                mesh = loaded.mesh
                archiveData = loaded.data
                meshRevision += 1
                documentName = url.lastPathComponent
                isLoading = false
                retryMaterials()
            } catch {
                guard !Task.isCancelled, let self, self.revision == requestedRevision else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func retryMaterials() {
        guard !isLoading, mesh != nil, let data = archiveData else { return }
        clearMaterials()
        let requestID = materialRequestID
        let documentRevision = revision
        isBakingMaterials = true
        materialTask = Task { [weak self, materialBaker] in
            do {
                let baked = try await materialBaker.load(
                    data: data,
                    options: MeshBakeOptions(colorSize: 512, normalSize: 256, materialSize: 128, atlasTextureSize: 512),
                    limits: ArchiveTextureLimits())
                try Task.checkCancellation()
                guard let self, self.revision == documentRevision, self.materialRequestID == requestID else { return }
                self.bakedMesh = baked
                self.materialRevision += 1
                self.isBakingMaterials = false
            } catch {
                guard !Task.isCancelled, let self, self.revision == documentRevision,
                    self.materialRequestID == requestID
                else { return }
                self.materialFailed(error.localizedDescription)
                self.isBakingMaterials = false
            }
        }
    }

    func materialFailed(_ cause: String) {
        bakedMesh = nil
        materialIssue = cause
    }

    func stop() {
        revision += 1
        loadTask?.cancel()
        clearMaterials()
        archiveData = nil
        mesh = nil
        isLoading = false
    }

    private func clearMaterials() {
        materialTask?.cancel()
        materialRequestID = UUID()
        bakedMesh = nil
        materialIssue = nil
        isBakingMaterials = false
    }
}
