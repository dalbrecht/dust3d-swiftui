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
            hasSourceBakedMaterials: sourceBakedMesh != nil
                && renderedMaterialRevision == meshRevision + materialRevision,
            hasLegacySurfaceDetails: materialSourceCapabilities.hasLegacySurfaceDetails,
            hasRenderedSurfaceDetails: bakedMesh != nil && renderedMaterialRevision == meshRevision + materialRevision,
            materialWarning: acceptedMaterialWarning)
    }
    private var renderedMaterialRevision: Int?
    // Retain only diagnostics from the accepted current preparation, including after a GPU failure.
    private var acceptedMaterialWarning: String?

    func materialsRendered(revision: Int) {
        guard materials != nil, revision == meshRevision + materialRevision else { return }
        renderedMaterialRevision = revision
    }

    private(set) var documentName = "Dust3D Viewer"
    private(set) var isLoading = false
    var pendingOpenRevision: Int? { isLoading ? revision : nil }
    private(set) var isBakingMaterials = false
    var isUpdatingMaterials: Bool {
        isBakingMaterials
            || ((materials != nil)
                && renderedMaterialRevision != meshRevision + materialRevision)
    }
    var pendingMaterialUpdateID: UUID? { isUpdatingMaterials ? materialRequestID : nil }
    private(set) var materialIssue: String?
    private(set) var meshRevision = 0
    private(set) var materialRevision = 0
    var errorMessage: String?
    private var rendererFailure: String?
    private var isRendererFailureDismissed = false
    var rendererError: String? { isRendererFailureDismissed ? nil : rendererFailure }
    func rendererRetryAction(ownsWindow: @escaping @MainActor () -> Bool = { true }) -> (@MainActor () -> Void)? {
        guard rendererFailure != nil, ownsWindow() else { return nil }
        let attemptID = rendererAttemptID
        return { [weak self] in
            guard ownsWindow() else { return }
            self?.retryRenderer(attemptID: attemptID)
        }
    }
    private(set) var rendererAttemptID = UUID()
    private(set) var cameraState = MeshCameraState()
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
                cameraState = MeshCameraState()
                resetRendererAttempt()
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

    func cancelOpen(revision: Int) {
        guard pendingOpenRevision == revision else { return }
        self.revision += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    var pendingCancellation: (() -> Void)? {
        if let revision = pendingOpenRevision {
            return { [weak self] in self?.cancelOpen(revision: revision) }
        }
        if let requestID = pendingMaterialUpdateID {
            return { [weak self] in
                guard let self, pendingOpenRevision == nil else { return }
                cancelMaterialUpdate(requestID: requestID)
            }
        }
        return nil
    }

    func reportRendererError(_ cause: String, attemptID: UUID) {
        guard mesh != nil, rendererAttemptID == attemptID else { return }
        rendererFailure = cause
        isRendererFailureDismissed = false
    }

    func dismissRendererError(attemptID: UUID) {
        guard rendererAttemptID == attemptID else { return }
        isRendererFailureDismissed = true
    }

    private func retryRenderer(attemptID: UUID) {
        guard rendererAttemptID == attemptID, rendererFailure != nil else { return }
        resetRendererAttempt()
        renderedMaterialRevision = nil
    }

    private func resetRendererAttempt() {
        rendererAttemptID = UUID()
        rendererFailure = nil
        isRendererFailureDismissed = false
    }

    func retryMaterials() {
        guard !isLoading, mesh != nil, let data = archiveData else { return }
        clearMaterials()
        let requestID = materialRequestID
        let acceptedMeshRevision = meshRevision
        isBakingMaterials = true
        materialTask = Task { [weak self, materialPreparation] in
            do {
                let prepared = try await materialPreparation.load(data: data, options: .init())
                try Task.checkCancellation()
                guard let self, self.meshRevision == acceptedMeshRevision, self.materialRequestID == requestID else {
                    return
                }
                self.materials = prepared
                self.acceptedMaterialWarning = prepared.preparationWarning
                self.materialRevision += 1
                self.isBakingMaterials = false
            } catch {
                guard !Task.isCancelled, let self, self.meshRevision == acceptedMeshRevision,
                    self.materialRequestID == requestID
                else { return }
                self.materialFailed(error.localizedDescription)
                self.isBakingMaterials = false
            }
        }
    }

    func cancelMaterialUpdate(requestID: UUID) {
        guard pendingMaterialUpdateID == requestID else { return }
        clearMaterials()
        materialTask = nil
        materialIssue = String(localized: "The material update was cancelled.")
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
        cameraState = MeshCameraState()
        resetRendererAttempt()
        materialSourceCapabilities = .unknown
        isLoading = false
    }

    private func clearMaterials() {
        materialTask?.cancel()
        materialRequestID = UUID()
        acceptedMaterialWarning = nil
        renderedMaterialRevision = nil
        materials = nil
        materialIssue = nil
        isBakingMaterials = false
    }
}
