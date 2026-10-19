import Dust3DKit
import Dust3DRendering
import Foundation
import Observation

@MainActor
@Observable
final class ViewerStore {
    private(set) var mesh: IndexedMesh?
    private(set) var materials: MeshMaterialContent?
    var bakedMesh: MeshWithBakedTextures? {
        guard case .baked(let value) = materials else { return nil }
        return value
    }
    var importedMaterials: ImportedMaterialRenderData? {
        guard case .imported(let value) = materials else { return nil }
        return value
    }
    var sourceBakedMesh: SourceBakedMesh? {
        guard case .sourceBaked(let value) = materials else { return nil }
        return value
    }
    private(set) var materialSourceCapabilities = MaterialSourceCapabilities.unknown
    var materialSourceIssue: String? { materialSourceCapabilities.issue?.localizedDescription }
    var previewCompatibilityWarning: String? {
        MaterialPreviewWarning.message(
            mesh?.warning ?? "",
            hasBakedMaterials: (bakedMesh != nil || sourceBakedMesh != nil)
                && renderedMaterialRevision == meshRevision + materialRevision,
            hasImportedMaterials: (importedMaterials != nil || sourceBakedMesh != nil)
                && renderedMaterialRevision == meshRevision + materialRevision,
            hasLegacySurfaceDetails: materialSourceCapabilities.hasLegacySurfaceDetails)
    }
    private var renderedMaterialRevision: Int?

    func materialsRendered(revision: Int) {
        guard materials != nil, revision == meshRevision + materialRevision else { return }
        renderedMaterialRevision = revision
    }

    private(set) var documentName = "Dust3D Viewer"
    private(set) var isLoading = false
    private(set) var isBakingMaterials = false
    var isUpdatingMaterials: Bool {
        isBakingMaterials
            || ((materials != nil)
                && renderedMaterialRevision != meshRevision + materialRevision)
    }
    private(set) var materialIssue: String?
    private(set) var meshRevision = 0
    private(set) var materialRevision = 0
    var errorMessage: String?
    private let service: any MeshFileSnapshotLoading
    private let materialPreparation: any ArchiveMaterialPreparing
    private(set) var loadTask: Task<Void, Never>?
    private(set) var materialTask: Task<Void, Never>?
    private var archiveData: Data?
    private var revision = 0
    private var materialRequestID = UUID()

    init(
        service: any MeshFileSnapshotLoading = MeshFileService(),
        materialBaker: any ArchiveTextureBaking = ArchiveTextureBakingService(),
        importedMaterialLoader: any ArchiveImportedMaterialLoading = ArchiveImportedMaterialService(),
        sourceMaterialBaker: any ArchiveSourceTextureBaking = ArchiveSourceTextureBakingService()
    ) {
        self.service = service
        materialPreparation = ArchiveMaterialPreparationService(
            importedLoader: importedMaterialLoader, proceduralBaker: materialBaker, sourceBaker: sourceMaterialBaker)
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
                materialSourceCapabilities = loaded.materialSourceCapabilities
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
        materialTask = Task { [weak self, materialPreparation] in
            do {
                let prepared = try await materialPreparation.load(data: data, options: .init())
                try Task.checkCancellation()
                guard let self, self.revision == documentRevision, self.materialRequestID == requestID else { return }
                self.materials = prepared
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

    func materialsFailed(_ cause: String, revision: Int) {
        guard revision == meshRevision + materialRevision, materials != nil else { return }
        materialFailed(cause)
    }

    func materialFailed(_ cause: String) {
        renderedMaterialRevision = nil
        materials = nil
        materialIssue = cause
    }

    func stop() {
        revision += 1
        loadTask?.cancel()
        clearMaterials()
        archiveData = nil
        mesh = nil
        materialSourceCapabilities = .unknown
        isLoading = false
    }

    private func clearMaterials() {
        materialTask?.cancel()
        materialRequestID = UUID()
        renderedMaterialRevision = nil
        materials = nil
        materialIssue = nil
        isBakingMaterials = false
    }
}
