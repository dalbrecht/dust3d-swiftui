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
        let decodedLimit = 64 * 1024 * 1024
        let metadata = try? PNGContainerMetadata(
            data: original, maximumEncodedBytes: ReferenceImageCodec.maximumEncodedBytes,
            maximumDecodedBytes: decodedLimit)
        let image: CGImage
        if let metadata, metadata.bitDepth == 16,
            metadata.colorType == 4 || (metadata.colorType == 0 && metadata.hasTransparencyKey)
        {
            // ImageIO can decode the source but cannot round-trip this PNG through its encoder.
            image = try ReferenceImageCodec.decodePNG(original)
        } else {
            image = try ReferenceImageCodec.decodePNG(ReferenceImageCodec.importPNG(original))
        }
        try Task.checkCancellation()
        let channels = try metadata.flatMap {
            try straightPNGChannels(original, metadata: $0, image: image, decodedLimit: decodedLimit)
        }
        return try ReferenceCompositionSource(
            image: image, crop: .init(size: .init(width: image.width, height: image.height)),
            straightRGBA: channels?.pixels, isIndexed: channels?.isIndexed ?? false, wideImage: channels?.wideImage)
    }

    private func straightPNGChannels(
        _ original: Data, metadata: PNGContainerMetadata, image: CGImage, decodedLimit: Int
    ) throws -> (pixels: Data?, isIndexed: Bool, wideImage: CGImage?)? {
        let width = image.width
        let height = image.height
        let isWide = metadata.bitDepth == 16 && [0, 2, 4, 6].contains(metadata.colorType)
        let isIndexedAlpha = [0, 3].contains(metadata.colorType) && metadata.hasTransparencyKey
        let isDirectAlpha =
            metadata.bitDepth == 8
            && ([4, 6].contains(metadata.colorType) || (metadata.colorType == 2 && metadata.hasTransparencyKey))
        guard isWide || isIndexedAlpha || isDirectAlpha,
            metadata.width == width, metadata.height == height,
            let rawImage = ReferenceImageCodec.straightStandardPNGImage(original)
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
            return (decoded.pixels, isIndexedAlpha, nil)
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
