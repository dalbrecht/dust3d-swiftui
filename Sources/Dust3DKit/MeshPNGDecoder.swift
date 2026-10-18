import CoreGraphics
import Foundation
import ImageIO

/// PNG decoding failures remain separate from document preservation and mesh generation.
public enum MeshPNGDecodingError: Error, Equatable, Sendable {
    case invalidLimits
    case encodedLimitExceeded
    case invalidPNG
    case decodedLimitExceeded
    case unsupportedPixelLayout
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
        let ceiling = 256 * 1024 * 1024
        guard (1...ceiling).contains(maximumEncodedBytes), (1...ceiling).contains(maximumDecodedBytes) else {
            throw MeshPNGDecodingError.invalidLimits
        }
        guard data.count <= maximumEncodedBytes else { throw MeshPNGDecodingError.encodedLimitExceeded }
        let dimensions = try validateContainer(data)
        let outputBytes = dimensions.width * dimensions.height * 4
        guard outputBytes <= maximumDecodedBytes else { throw MeshPNGDecodingError.decodedLimitExceeded }
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options),
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
            image.width == dimensions.width, image.height == dimensions.height,
            let providerData = image.dataProvider?.data, let storage = CFDataGetBytePtr(providerData)
        else { throw MeshPNGDecodingError.invalidPNG }
        let layout = try SampleLayout(image)
        let storageSpan = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !storageSpan.overflow, image.bytesPerRow >= image.width * layout.bytesPerPixel,
            CFDataGetLength(providerData) >= storageSpan.partialValue
        else { throw MeshPNGDecodingError.invalidPNG }
        var pixels = Data(count: outputBytes)
        try pixels.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            for row in 0..<image.height {
                try Task.checkCancellation()
                for column in 0..<image.width {
                    let inputOffset = row * image.bytesPerRow + column * layout.bytesPerPixel
                    let outputOffset = (row * image.width + column) * 4
                    var pixel = try layout.rgba(storage.advanced(by: inputOffset))
                    if dimensions.zerosTransparentGray && pixel.3 == 0 { pixel = (0, 0, 0, 0) }
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

    private static func validateContainer(_ data: Data) throws
        -> (width: Int, height: Int, zerosTransparentGray: Bool)
    {
        let bytes = Array(data)
        guard bytes.count >= 33, Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else {
            throw MeshPNGDecodingError.invalidPNG
        }
        func integer(_ offset: Int) -> Int {
            bytes[offset..<offset + 4].reduce(0) { $0 * 256 + Int($1) }
        }
        guard integer(8) == 13, Array(bytes[12..<16]) == Array("IHDR".utf8) else {
            throw MeshPNGDecodingError.invalidPNG
        }
        let width = integer(16)
        let height = integer(20)
        guard (1...8192).contains(width), (1...8192).contains(height) else {
            throw MeshPNGDecodingError.decodedLimitExceeded
        }
        var offset = 8
        var zerosTransparentGray = false
        while offset <= bytes.count - 12 {
            let count = integer(offset)
            guard count <= bytes.count - offset - 12 else { throw MeshPNGDecodingError.invalidPNG }
            let kind = Array(bytes[offset + 4..<offset + 8])
            if bytes[25] == 0 && [2, 4, 8].contains(bytes[24]) && kind == Array("tRNS".utf8) {
                zerosTransparentGray = true
            }
            if kind == Array("IEND".utf8) {
                guard count == 0, offset + 12 == bytes.count else { throw MeshPNGDecodingError.invalidPNG }
                return (width, height, zerosTransparentGray)
            }
            offset += count + 12
        }
        throw MeshPNGDecodingError.invalidPNG
    }
}

private struct SampleLayout {
    let bytesPerPixel: Int
    let bytesPerSample: Int
    let isLittleEndian: Bool
    let model: CGColorSpaceModel
    let hasAlpha: Bool
    let palette: [UInt8]

    init(_ image: CGImage) throws {
        guard let space = image.colorSpace,
            image.bitsPerComponent == 8 || image.bitsPerComponent == 16,
            image.bitsPerPixel % image.bitsPerComponent == 0,
            [.none, .last, .noneSkipLast].contains(image.alphaInfo)
        else { throw MeshPNGDecodingError.unsupportedPixelLayout }
        model = space.model
        bytesPerSample = image.bitsPerComponent / 8
        bytesPerPixel = image.bitsPerPixel / 8
        hasAlpha = image.alphaInfo == .last
        isLittleEndian = image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder16Little
        palette = space.colorTable ?? []
        let channels = image.bitsPerPixel / image.bitsPerComponent
        switch model {
        case .rgb:
            guard channels == (image.alphaInfo == .none ? 3 : 4) else {
                throw MeshPNGDecodingError.unsupportedPixelLayout
            }
        case .monochrome:
            guard channels == (hasAlpha ? 2 : 1) else { throw MeshPNGDecodingError.unsupportedPixelLayout }
        case .indexed:
            guard bytesPerPixel == 1, space.baseColorSpace?.model == .rgb, !palette.isEmpty,
                palette.count % 3 == 0
            else { throw MeshPNGDecodingError.unsupportedPixelLayout }
        default: throw MeshPNGDecodingError.unsupportedPixelLayout
        }
    }

    func rgba(_ source: UnsafePointer<UInt8>) throws -> (UInt8, UInt8, UInt8, UInt8) {
        func sample(_ channel: Int) -> UInt8 {
            let offset = channel * bytesPerSample
            guard bytesPerSample == 2 else { return source[offset] }
            let first = Int(source[offset])
            let second = Int(source[offset + 1])
            let value = isLittleEndian ? first + second * 256 : first * 256 + second
            // Match QRgba64's nearest 16-to-8 conversion, including half-step edges.
            let rounded = value + 128
            return UInt8((rounded - (rounded >> 8)) >> 8)
        }
        if model == .indexed {
            let offset = Int(source[0]) * 3
            guard offset + 2 < palette.count else { throw MeshPNGDecodingError.invalidPNG }
            return (palette[offset], palette[offset + 1], palette[offset + 2], 255)
        }
        if model == .monochrome {
            let gray = sample(0)
            return (gray, gray, gray, hasAlpha ? sample(1) : 255)
        }
        return (sample(0), sample(1), sample(2), hasAlpha ? sample(3) : 255)
    }
}
