import CoreGraphics
import Dust3DDocument
import Foundation
import ImageIO

/// PNG decoding failures remain separate from document preservation and mesh generation.
public enum MeshPNGDecodingError: LocalizedError, Equatable, Sendable {
    case invalidLimits
    case encodedLimitExceeded
    case invalidPNG
    case decodedLimitExceeded
    case unsupportedPixelLayout

    /// Specific decoder cause suitable for a retained-asset diagnostic.
    public var errorDescription: String? {
        switch self {
        case .invalidLimits: return "The PNG decoding limits are invalid."
        case .encodedLimitExceeded: return "The encoded PNG exceeds the configured input limit."
        case .invalidPNG: return "The image is not a complete, supported PNG."
        case .decodedLimitExceeded: return "The decoded PNG exceeds its dimension or storage limit."
        case .unsupportedPixelLayout: return "The PNG pixel layout is not supported."
        }
    }
}

/// Apple image boundary for source-encoded, unassociated RGBA8 bake inputs.
public enum MeshPNGDecoder {
    /// Decode PNG samples without EXIF transforms, color conversion or premultiplication.
    /// Keyed transparent 2/4/8-bit grayscale becomes black to match Qt's PNG loader;
    /// other depths, explicit alpha and RGB keys preserve hidden RGB samples.
    /// - Parameters:
    ///   - data: Original PNG bytes, never modified.
    ///   - imageID: Opaque identity forwarded to the baking SDK for validation.
    ///   - maximumEncodedBytes: Positive encoded quota, at most 256 MiB.
    ///   - maximumDecodedBytes: Positive RGBA output quota, at most 256 MiB.
    /// - Returns: Owned, tightly packed RGBA8 rows in encoded scanline order.
    /// - Throws: `MeshPNGDecodingError` for invalid limits, malformed PNG, excess
    ///   dimensions/storage or unsupported ImageIO sample layouts; `CancellationError`
    ///   at cooperative row boundaries.
    /// - Note: Quotas cover encoded input and final output, not ImageIO workspace.
    ///   Call outside the main actor; synchronous ImageIO work cannot be preempted.
    public static func decode(
        _ data: Data, imageID: String,
        maximumEncodedBytes: Int = 32 * 1024 * 1024,
        maximumDecodedBytes: Int = 256 * 1024 * 1024
    ) throws -> MeshBakeImage {
        do {
            return try decodePixels(
                data, imageID: imageID, maximumEncodedBytes: maximumEncodedBytes,
                maximumDecodedBytes: maximumDecodedBytes)
        } catch let error as ImageSampleError {
            switch error {
            case .unsupportedLayout: throw MeshPNGDecodingError.unsupportedPixelLayout
            case .invalidPixels: throw MeshPNGDecodingError.invalidPNG
            }
        }
    }

    private static func decodePixels(
        _ data: Data, imageID: String, maximumEncodedBytes: Int,
        maximumDecodedBytes: Int
    ) throws -> MeshBakeImage {
        let dimensions: PNGContainerMetadata
        do {
            dimensions = try PNGContainerMetadata(
                data: data, maximumEncodedBytes: maximumEncodedBytes, maximumDecodedBytes: maximumDecodedBytes)
        } catch let error as PNGContainerError {
            switch error {
            case .invalidLimits: throw MeshPNGDecodingError.invalidLimits
            case .encodedLimitExceeded: throw MeshPNGDecodingError.encodedLimitExceeded
            case .invalidPNG: throw MeshPNGDecodingError.invalidPNG
            case .decodedLimitExceeded: throw MeshPNGDecodingError.decodedLimitExceeded
            }
        }
        let outputBytes = dimensions.width * dimensions.height * 4
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options),
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
            image.width == dimensions.width, image.height == dimensions.height,
            let providerData = image.dataProvider?.data, let storage = CFDataGetBytePtr(providerData)
        else { throw MeshPNGDecodingError.invalidPNG }
        let layout = try ImageSampleLayout(image)
        let storageSpan = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !storageSpan.overflow, image.bytesPerRow >= image.width * layout.bytesPerPixel,
            CFDataGetLength(providerData) >= storageSpan.partialValue
        else { throw MeshPNGDecodingError.invalidPNG }
        let zerosTransparentGray =
            dimensions.hasTransparencyKey && dimensions.colorType == 0 && [2, 4, 8].contains(dimensions.bitDepth)
        var pixels = Data(count: outputBytes)
        try pixels.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            for row in 0..<image.height {
                try Task.checkCancellation()
                for column in 0..<image.width {
                    let inputOffset = row * image.bytesPerRow + column * layout.bytesPerPixel
                    let outputOffset = (row * image.width + column) * 4
                    var pixel = try layout.rgba(storage.advanced(by: inputOffset))
                    if zerosTransparentGray && pixel.3 == 0 { pixel = (0, 0, 0, 0) }
                    output[outputOffset] = pixel.0
                    output[outputOffset + 1] = pixel.1
                    output[outputOffset + 2] = pixel.2
                    output[outputOffset + 3] = pixel.3
                }
            }
        }
        return MeshBakeImage(
            imageID: imageID, width: image.width, height: image.height,
            rowStride: image.width * 4, pixels: pixels)
    }

}
