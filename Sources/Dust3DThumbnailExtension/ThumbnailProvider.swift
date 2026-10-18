import Dust3DRendering
import Foundation
import QuickLookThumbnailing

/// System thumbnail requests consume only copied URL/size inputs and immutable preview output.
final class ThumbnailProvider: QLThumbnailProvider {
    private let service = FilePreviewDocumentService()

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: sending @escaping (QLThumbnailReply?, (any Error)?) -> Void
    ) {
        // The SDK explicitly permits asynchronous completion after this method returns.
        let url = request.fileURL
        let maximumSize = request.maximumSize
        let scale = request.scale
        let service = service
        Task { @MainActor in
            do {
                let document = try await service.load(url: url)
                let image: FilePreviewImage
                if let baked = document.bakedMesh {
                    image = try await FilePreviewRenderer.render(
                        bakedMesh: baked, maximumSize: maximumSize, scale: scale)
                } else if let mesh = document.mesh {
                    image = try await FilePreviewRenderer.render(mesh: mesh, maximumSize: maximumSize, scale: scale)
                } else {
                    throw FilePreviewError.unavailable("This document has no visible mesh to thumbnail.")
                }
                try Task.checkCancellation()
                let drawing = try image.makeDrawing()
                handler(QLThumbnailReply(contextSize: image.pointSize, drawing: drawing), nil)
            } catch { handler(nil, error) }
        }
    }
}
