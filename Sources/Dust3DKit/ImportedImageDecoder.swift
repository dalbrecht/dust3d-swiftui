import CoreGraphics
import Dust3DDocument
import Foundation
import ImageIO

/// Owned source samples; material factors and sampler policy have not been applied.
public struct ImportedDecodedImage: Sendable, Equatable {
    public let modelID: String
    public let width: Int
    public let height: Int
    public let rowStride: Int
    public let pixels: Data
}

/// Platform pixel failures remain distinct from JPEG envelope/quota failures.
public enum MeshJPEGDecodingError: LocalizedError, Equatable, Sendable {
    case invalidJPEG
    case unsupportedPixelLayout

    public var errorDescription: String? {
        switch self {
        case .invalidJPEG: return "The image is not a complete, supported JPEG."
        case .unsupportedPixelLayout: return "The JPEG pixel layout is not supported."
        }
    }
}

/// Bounded imported-image decoding without transforms, color conversion or premultiplication.
public enum ImportedImageDecoder {
    /// Decode source samples outside the main actor, preserving encoded scanline order.
    /// - Parameters:
    ///   - image: Independently owned encoded PNG or JPEG bytes.
    ///   - modelID: Original model identity, retained without normalization.
    ///   - maximumEncodedBytes: Positive input ceiling, at most 256 MiB.
    ///   - maximumDecodedBytes: Positive tightly packed RGBA8 ceiling, at most 256 MiB.
    /// - Returns: Owned straight RGBA8 pixels, without material factor multiplication.
    /// - Throws: MeshPNGDecodingError, JPEGContainerError, MeshJPEGDecodingError or CancellationError.
    /// - Note: Limits exclude ImageIO workspace. Synchronous codec work cannot be preempted.
    /// - Example: try ImportedImageDecoder.decode(image, modelID: material.id)
    public static func decode(
        _ image: ImportedEncodedImage, modelID: String,
        maximumEncodedBytes: Int = 32 * 1024 * 1024,
        maximumDecodedBytes: Int = 256 * 1024 * 1024
    ) throws -> ImportedDecodedImage {
        try Task.checkCancellation()
        switch image.encoding {
        case .png:
            let value = try MeshPNGDecoder.decode(
                image.bytes, imageID: modelID,
                maximumEncodedBytes: maximumEncodedBytes, maximumDecodedBytes: maximumDecodedBytes,
                preservesTransparentGrayRGB: true)
            return ImportedDecodedImage(
                modelID: modelID, width: value.width, height: value.height,
                rowStride: value.rowStride, pixels: value.pixels)
        case .jpeg:
            return try decodeJPEG(
                image.bytes, modelID: modelID, maximumEncodedBytes: maximumEncodedBytes,
                maximumDecodedBytes: maximumDecodedBytes)
        }
    }

    private static func decodeJPEG(
        _ data: Data, modelID: String, maximumEncodedBytes: Int,
        maximumDecodedBytes: Int
    ) throws -> ImportedDecodedImage {
        let dimensions = try JPEGContainerMetadata(
            data: data, maximumEncodedBytes: maximumEncodedBytes,
            maximumDecodedBytes: maximumDecodedBytes)
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options),
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
            image.width == dimensions.width, image.height == dimensions.height,
            let provider = image.dataProvider?.data, let storage = CFDataGetBytePtr(provider)
        else {
            throw MeshJPEGDecodingError.invalidJPEG
        }
        do {
            let layout = try ImageSampleLayout(image)
            let span = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
            guard !span.overflow, image.bytesPerRow >= image.width * layout.bytesPerPixel,
                CFDataGetLength(provider) >= span.partialValue
            else { throw MeshJPEGDecodingError.invalidJPEG }
            var pixels = Data(count: dimensions.width * dimensions.height * 4)
            try pixels.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
                for row in 0..<image.height {
                    try Task.checkCancellation()
                    for column in 0..<image.width {
                        let pixel = try layout.rgba(
                            storage.advanced(by: row * image.bytesPerRow + column * layout.bytesPerPixel))
                        let offset = (row * image.width + column) * 4
                        output[offset] = pixel.0
                        output[offset + 1] = pixel.1
                        output[offset + 2] = pixel.2
                        output[offset + 3] = pixel.3
                    }
                }
            }
            return ImportedDecodedImage(
                modelID: modelID, width: image.width, height: image.height,
                rowStride: image.width * 4, pixels: pixels)
        } catch let error as ImageSampleError {
            switch error {
            case .unsupportedLayout: throw MeshJPEGDecodingError.unsupportedPixelLayout
            case .invalidPixels: throw MeshJPEGDecodingError.invalidJPEG
            }
        }
    }
}

extension ImportedMaterialService {
    /// Decode encoded model-image bytes on the service actor.
    /// - Parameters:
    ///   - image: Independently owned source bytes.
    ///   - modelID: Original opaque identity.
    ///   - maximumEncodedBytes: Input quota, at most 256 MiB.
    ///   - maximumDecodedBytes: RGBA8 output quota, at most 256 MiB.
    /// - Returns: Independent pixels without material factors applied.
    /// - Throws: Original decoder error or cancellation before/after synchronous work.
    /// - Example: try await service.decodeImage(image, modelID: material.id)
    public func decodeImage(
        _ image: ImportedEncodedImage, modelID: String,
        maximumEncodedBytes: Int = 32 * 1024 * 1024,
        maximumDecodedBytes: Int = 256 * 1024 * 1024
    ) async throws -> ImportedDecodedImage {
        try Task.checkCancellation()
        let result = try ImportedImageDecoder.decode(
            image, modelID: modelID,
            maximumEncodedBytes: maximumEncodedBytes, maximumDecodedBytes: maximumDecodedBytes)
        try Task.checkCancellation()
        return result
    }
}
