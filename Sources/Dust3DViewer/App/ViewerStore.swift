import Dust3DKit
import Foundation
import Observation

@MainActor
@Observable
final class ViewerStore {
    private(set) var mesh: IndexedMesh?
    private(set) var documentName = "Dust3D Viewer"
    private(set) var isLoading = false
    private(set) var meshRevision = 0
    var errorMessage: String?
    private let service = MeshFileService()
    private var loadTask: Task<Void, Never>?
    private var revision = 0

    func open(_ url: URL) {
        loadTask?.cancel()
        revision += 1
        let requestedRevision = revision
        isLoading = true
        errorMessage = nil
        loadTask = Task { [weak self, service] in
            do {
                let loaded = try await service.loadIndexed(url: url)
                guard let self, self.revision == requestedRevision else { return }
                mesh = loaded
                meshRevision += 1
                documentName = url.lastPathComponent
                isLoading = false
            } catch is CancellationError {
                // A newer request owns the loading state.
            } catch {
                guard let self, self.revision == requestedRevision else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
