import Dust3DRendering
import Foundation
import QuickLookThumbnailing
import os

/// System thumbnail requests consume only copied URL/size inputs and immutable preview output.
final class ThumbnailProvider: QLThumbnailProvider {
    private let service = FilePreviewDocumentService()
    private static let logger = Logger(subsystem: "org.dust3d.editor.thumbnail", category: "Rendering")

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: sending @escaping (QLThumbnailReply?, (any Error)?) -> Void
    ) {
        // The SDK explicitly permits asynchronous completion after this method returns.
        let url = request.fileURL
        let maximumSize = request.maximumSize
        let scale = request.scale
        let service = service
        let operationID = UUID().uuidString
        Self.logger.notice("operation=thumbnailStarted requestID=\(operationID, privacy: .public)")
        Task { @MainActor in
            do {
                let document = try await service.load(url: url)
                let rendered = try await FilePreviewRenderer.render(
                    document: document, maximumSize: maximumSize, scale: scale)
                if let issue = rendered.materialError {
                    Self.logger.warning(
                        "Thumbnail operation \(operationID, privacy: .public): using ordinary geometry after material preview failed: \(issue.localizedDescription, privacy: .private)"
                    )
                }
                let image = rendered.image
                try Task.checkCancellation()
                let drawing = try image.makeDrawing()
                handler(QLThumbnailReply(contextSize: image.pointSize, drawing: drawing), nil)
            } catch {
                let failure = error as NSError
                Self.logger.error(
                    "operation=thumbnailFailed requestID=\(operationID, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code) cause=\(error.localizedDescription, privacy: .private)"
                )
                handler(nil, error)
            }
        }
    }
}
