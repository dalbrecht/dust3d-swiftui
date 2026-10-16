import Dust3DEditorModel
import Foundation

protocol ReferenceCompositionServing: Sendable {
    func importSource(url: URL) async throws -> ReferenceCompositionSource
    func compose(front: ReferenceCompositionSource?, side: ReferenceCompositionSource?) async throws
        -> ReferenceCompositionResult
}

/// Raster import/composition execute on this actor, independently of observable draft state.
actor ReferenceCompositionService: ReferenceCompositionServing {
    private let images = ReferenceImageService()

    func importSource(url: URL) async throws -> ReferenceCompositionSource {
        let png = try await images.importImage(url: url)
        try Task.checkCancellation()
        let image = try ReferenceImageCodec.decodePNG(png)
        return try ReferenceCompositionSource(
            image: image, crop: .init(size: .init(width: image.width, height: image.height)))
    }

    func compose(front: ReferenceCompositionSource?, side: ReferenceCompositionSource?) throws
        -> ReferenceCompositionResult
    {
        try ReferenceCompositionRaster.compose(front: front, side: side)
    }
}
