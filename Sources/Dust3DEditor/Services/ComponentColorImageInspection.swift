import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Foundation
import Observation

struct ComponentColorImageInspectionRequest: Sendable {
    let document: Dust3DDocument
    let asset: DocumentColorImageAsset
    let context: CanvasAdjustmentTarget
}

/// A local inspector thumbnail request, independent of image assignment and document history.
@MainActor @Observable
final class ComponentColorImageInspection {
    private(set) var request: ComponentColorImageInspectionRequest?
    private(set) var image: CGImage?
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private let load: @Sendable (ComponentColorImageInspectionRequest) async throws -> CGImage

    var isLoading: Bool { task != nil }

    convenience init() {
        let service = ColorImageService()
        self.init(load: { request in
            try await service.previewRetainedImage(document: request.document, asset: request.asset)
        })
    }

    init(load: @escaping @Sendable (ComponentColorImageInspectionRequest) async throws -> CGImage) {
        self.load = load
    }

    @discardableResult
    func inspect(
        _ request: ComponentColorImageInspectionRequest, isCurrent: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>? {
        guard isCurrent() else { return nil }
        cancel()
        self.request = request
        let id = UUID()
        requestID = id
        let pending = Task { [weak self, load] in
            let result: Result<CGImage, any Error>
            do {
                result = .success(try await load(request))
            } catch {
                result = .failure(error)
            }
            guard let self, requestID == id else { return }
            guard !Task.isCancelled, isCurrent() else {
                cancel()
                return
            }
            task = nil
            switch result {
            case .success(let thumbnail): image = thumbnail
            case .failure(let error): errorMessage = EditorStore.message(error)
            }
        }
        task = pending
        return pending
    }

    func cancel() {
        task?.cancel()
        task = nil
        requestID = nil
        request = nil
        image = nil
        errorMessage = nil
    }
}
