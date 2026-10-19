import Dust3DKit
import Foundation
import Observation

private enum PreparedViewerMaterials: Sendable {
    case baked(MeshWithBakedTextures)
    case imported(ImportedMaterialRenderData)
}

@MainActor
@Observable
final class ViewerStore {
    private(set) var mesh: IndexedMesh?
    private(set) var bakedMesh: MeshWithBakedTextures?
    private(set) var importedMaterials: ImportedMaterialRenderData?
    private(set) var materialSourceCapabilities = MaterialSourceCapabilities.unknown
    var materialSourceIssue: String? { materialSourceCapabilities.issue?.localizedDescription }
    var previewCompatibilityWarning: String? {
        MaterialPreviewWarning.message(
            mesh?.warning ?? "",
            hasBakedMaterials: bakedMesh != nil && renderedMaterialRevision == meshRevision + materialRevision,
            hasImportedMaterials: importedMaterials != nil
                && renderedMaterialRevision == meshRevision + materialRevision,
            hasLegacySurfaceDetails: materialSourceCapabilities.hasLegacySurfaceDetails)
    }
    private var renderedMaterialRevision: Int?

    func materialsRendered(revision: Int) {
        guard bakedMesh != nil || importedMaterials != nil, revision == meshRevision + materialRevision else { return }
        renderedMaterialRevision = revision
    }

    private(set) var documentName = "Dust3D Viewer"
    private(set) var isLoading = false
    private(set) var isBakingMaterials = false
    var isUpdatingMaterials: Bool {
        isBakingMaterials
            || ((bakedMesh != nil || importedMaterials != nil)
                && renderedMaterialRevision != meshRevision + materialRevision)
    }
    private(set) var materialIssue: String?
    private(set) var meshRevision = 0
    private(set) var materialRevision = 0
    var errorMessage: String?
    private let service: any MeshFileSnapshotLoading
    private let materialBaker: any ArchiveTextureBaking
    private let importedMaterialLoader: any ArchiveImportedMaterialLoading
    private(set) var loadTask: Task<Void, Never>?
    private(set) var materialTask: Task<Void, Never>?
    private var archiveData: Data?
    private var revision = 0
    private var materialRequestID = UUID()

    init(
        service: any MeshFileSnapshotLoading = MeshFileService(),
        materialBaker: any ArchiveTextureBaking = ArchiveTextureBakingService(),
        importedMaterialLoader: any ArchiveImportedMaterialLoading = ArchiveImportedMaterialService()
    ) {
        self.service = service
        self.materialBaker = materialBaker
        self.importedMaterialLoader = importedMaterialLoader
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
        materialTask = Task { [weak self, materialBaker, importedMaterialLoader] in
            do {
                let prepared: PreparedViewerMaterials
                if let imported = try await importedMaterialLoader.loadIfPresent(data: data, limits: .init()) {
                    prepared = .imported(imported)
                } else {
                    try Task.checkCancellation()
                    prepared = .baked(
                        try await materialBaker.load(
                            data: data,
                            options: MeshBakeOptions(
                                colorSize: 512, normalSize: 256, materialSize: 128, atlasTextureSize: 512),
                            limits: ArchiveTextureLimits()))
                }
                try Task.checkCancellation()
                guard let self, self.revision == documentRevision, self.materialRequestID == requestID else { return }
                switch prepared {
                case .baked(let baked):
                    self.bakedMesh = baked
                    self.importedMaterials = nil
                case .imported(let imported):
                    self.importedMaterials = imported
                    self.bakedMesh = nil
                }
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
        guard revision == meshRevision + materialRevision, bakedMesh != nil || importedMaterials != nil else { return }
        materialFailed(cause)
    }

    func materialFailed(_ cause: String) {
        renderedMaterialRevision = nil
        bakedMesh = nil
        importedMaterials = nil
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
        bakedMesh = nil
        importedMaterials = nil
        materialIssue = nil
        isBakingMaterials = false
    }
}
