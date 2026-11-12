import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
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
        let original = try await images.readEncodedImage(url: url)
        let png = try ReferenceImageCodec.importPNG(original)
        try Task.checkCancellation()
        let image = try ReferenceImageCodec.decodePNG(png)
        let channels = try straightPNGChannels(original, width: image.width, height: image.height)
        return try ReferenceCompositionSource(
            image: image, crop: .init(size: .init(width: image.width, height: image.height)),
            straightRGBA: channels?.pixels, isIndexed: channels?.isIndexed ?? false, wideImage: channels?.wideImage)
    }

    private func straightPNGChannels(_ original: Data, width: Int, height: Int) throws -> (
        pixels: Data?, isIndexed: Bool, wideImage: CGImage?
    )? {
        let decodedLimit = 64 * 1024 * 1024
        guard
            let metadata = try? PNGContainerMetadata(
                data: original, maximumEncodedBytes: ReferenceImageCodec.maximumEncodedBytes,
                maximumDecodedBytes: decodedLimit),
            metadata.bitDepth == 16 && metadata.colorType == 6
                || metadata.colorType == 3 && metadata.hasTransparencyKey
                || (metadata.bitDepth == 8
                    && (metadata.colorType == 6 || (metadata.colorType == 2 && metadata.hasTransparencyKey))),
            metadata.width == width, metadata.height == height,
            let rawImage = ReferenceImageCodec.straightSRGBImage(original)
        else { return nil }
        if metadata.bitDepth == 16 {
            guard rawImage.bitsPerComponent == 16, rawImage.width == width, rawImage.height == height,
                (try? ImageSampleLayout(rawImage)) != nil
            else { return nil }
            return (nil, false, rawImage)
        }
        do {
            let decoded = try MeshPNGDecoder.decode(
                original, imageID: "reference-image", maximumDecodedBytes: decodedLimit
            )
            return (decoded.pixels, metadata.colorType == 3, nil)
        } catch is MeshPNGDecodingError {
            // The preview decoder can still display PNG layouts unsupported by the sample decoder.
            return nil
        }
    }

    func compose(front: ReferenceCompositionSource?, side: ReferenceCompositionSource?) throws
        -> ReferenceCompositionResult
    {
        try ReferenceCompositionRaster.compose(front: front, side: side)
    }
}
