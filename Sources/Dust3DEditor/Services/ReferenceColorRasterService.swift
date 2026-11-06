import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import ImageIO

enum ReferenceColorRasterError: Error, Equatable, Sendable {
    case missingReference
    case invalidLimits
    case fittedLimitExceeded
    case unsupportedOrientation(Int)
    case invalidLogicalHeight
    case unsupportedDisplayProfile
    case incompatibleGrayPixels
    case displayImageUnavailable
}

/// Immutable raster and source identity captured from one document, independent of the preview-image cache.
struct ReferenceColorRasterResult: Sendable {
    let referencePNG: Data
    let referenceSize: ReferencePixelSize
    let raster: ReferenceColorRaster
    /// Exactly the fitted sample values, represented in a pixel layout compatible with the original profile.
    let displayImage: CGImage
    /// Original profile metadata, without converting the sampled channel values into another color space.
    let sourceColorSpace: CGColorSpace?
}

protocol ReferenceColorRasterServing: Sendable {
    func prepare(document: Dust3DDocument, logicalHeight: Double) async throws -> ReferenceColorRasterResult
}

/// One window's off-main reference sampling boundary; no mutable NSImage/CGContext state crosses actors.
actor ReferenceColorRasterService: ReferenceColorRasterServing {
    func prepare(document: Dust3DDocument, logicalHeight: Double) throws -> ReferenceColorRasterResult {
        try ReferenceColorRasterCodec.prepare(document: document, logicalHeight: logicalHeight)
    }

    func prepare(document: Dust3DDocument, fittedSize: ReferencePixelSize) throws -> ReferenceColorRasterResult {
        try ReferenceColorRasterCodec.prepare(document: document, fittedSize: fittedSize)
    }
}

/// Bounded owned samples for a caller-selected logical raster grid, never an inferred Retina backing size.
/// Output limits exclude retained archive/input copies, ImageIO workspace and transient owned buffers.
enum ReferenceColorRasterCodec {
    static let maximumPixelBytes = 64 * 1024 * 1024

    /// Decode retained reference bytes, normalize orientation and fit with an explicit aliased sample grid.
    /// Call outside the UI actor. No native engine, catalog or archive extraction is involved.
    /// The existing PNG decoder matches audited Qt sample rules, including its depth-specific keyed-gray
    /// exception. Explicit alpha/RGB-key hidden RGB and low-alpha channels are not premultiplied here.
    /// Coordinate fitting follows Qt's aliased grid; PNG alpha/depth conversion parity remains under test.
    static func prepare(
        document: Dust3DDocument, fittedSize: ReferencePixelSize,
        maximumDecodedBytes: Int = maximumPixelBytes, maximumFittedBytes: Int = maximumPixelBytes
    ) throws -> ReferenceColorRasterResult {
        try prepare(
            document: document, maximumDecodedBytes: maximumDecodedBytes, maximumFittedBytes: maximumFittedBytes
        ) { _ in fittedSize }
    }

    /// Derive a bounded explicit 1x logical grid from freshly decoded oriented dimensions, not a UI image cache.
    static func prepare(
        document: Dust3DDocument, logicalHeight: Double,
        maximumDecodedBytes: Int = maximumPixelBytes, maximumFittedBytes: Int = maximumPixelBytes
    ) throws -> ReferenceColorRasterResult {
        guard logicalHeight.isFinite, logicalHeight > 0, logicalHeight <= 8192 else {
            throw ReferenceColorRasterError.invalidLogicalHeight
        }
        return try prepare(
            document: document, maximumDecodedBytes: maximumDecodedBytes, maximumFittedBytes: maximumFittedBytes
        ) { reference in
            let width = (Double(reference.width) / Double(reference.height) * logicalHeight).rounded(.up)
            let height = logicalHeight.rounded(.up)
            guard width > 0, width <= 8192, height > 0, height <= 8192,
                width * height <= 16 * 1024 * 1024
            else { throw ReferenceColorRasterError.fittedLimitExceeded }
            return try ReferencePixelSize(width: Int(width), height: Int(height))
        }
    }

    private static func prepare(
        document: Dust3DDocument, maximumDecodedBytes: Int, maximumFittedBytes: Int,
        fitting: (ReferencePixelSize) throws -> ReferencePixelSize
    ) throws -> ReferenceColorRasterResult {
        try Task.checkCancellation()
        guard maximumDecodedBytes > 0, maximumDecodedBytes <= maximumPixelBytes,
            maximumFittedBytes > 0, maximumFittedBytes <= maximumPixelBytes
        else { throw ReferenceColorRasterError.invalidLimits }
        guard let count = document.referenceImageByteCount else { throw ReferenceColorRasterError.missingReference }
        guard count <= ReferenceImageCodec.maximumEncodedBytes else { throw ReferenceImageError.imageTooLarge }
        guard let png = document.referenceImagePNG else { throw ReferenceColorRasterError.missingReference }
        let decoded = try MeshPNGDecoder.decode(
            png, imageID: "reference", maximumEncodedBytes: ReferenceImageCodec.maximumEncodedBytes,
            maximumDecodedBytes: maximumDecodedBytes)
        try Task.checkCancellation()
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(png as CFData, options),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let image = CGImageSourceCreateImageAtIndex(source, 0, options)
        else { throw MeshPNGDecodingError.invalidPNG }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard (1...8).contains(orientation) else { throw ReferenceColorRasterError.unsupportedOrientation(orientation) }
        let swapsAxes = orientation >= 5
        let size = try ReferencePixelSize(
            width: swapsAxes ? decoded.height : decoded.width, height: swapsAxes ? decoded.width : decoded.height)
        let fittedSize = try fitting(size)
        let fittedBytes = fittedSize.width * fittedSize.height * 4
        guard fittedBytes <= maximumFittedBytes else { throw ReferenceColorRasterError.fittedLimitExceeded }
        try Task.checkCancellation()
        let metadata = try PNGContainerMetadata(data: png)
        let isResized = fittedSize != size
        // Indexed/low-depth grayscale transforms copy palette entries instead of
        // painting associated-alpha samples. Original-size copies retain RGB too.
        let paintsAlpha =
            isResized && (metadata.colorType != 3)
            && !(metadata.colorType == 0 && metadata.bitDepth <= 8)
        let paletteGrid =
            metadata.colorType == 3
            || (metadata.colorType == 0
                && (metadata.bitDepth < 8
                    || (metadata.bitDepth == 8 && metadata.hasTransparencyKey)))
        let horizontalRatio = Double(size.width) / Double(fittedSize.width)
        let verticalRatio = Double(size.height) / Double(fittedSize.height)
        let fixedAffine =
            horizontalRatio > 1.0 / 256 && horizontalRatio < 100
            && verticalRatio > 1.0 / 256 && verticalRatio < 100
        let wideLayout = try ImageSampleLayout(image)
        guard let wideData = image.dataProvider?.data, let wideStorage = CFDataGetBytePtr(wideData) else {
            throw MeshPNGDecodingError.invalidPNG
        }
        defer { withExtendedLifetime(wideData) {} }
        let wideSpan = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !wideSpan.overflow, image.bytesPerRow >= image.width * wideLayout.bytesPerPixel,
            CFDataGetLength(wideData) >= wideSpan.partialValue
        else { throw MeshPNGDecodingError.invalidPNG }
        var fitted = Data(count: fittedBytes)
        try fitted.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            try decoded.pixels.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
                // All dimensions are validated <=8192; these integer products stay far below Int's limit.
                for y in 0..<fittedSize.height {
                    try Task.checkCancellation()
                    let orientedY = fittedCoordinate(
                        y, source: size.height, destination: fittedSize.height, scanline: false, palette: paletteGrid,
                        fixedAffine: fixedAffine)
                    for x in 0..<fittedSize.width {
                        let orientedX = fittedCoordinate(
                            x, source: size.width, destination: fittedSize.width, scanline: true, palette: paletteGrid,
                            fixedAffine: fixedAffine)
                        let original = originalPoint(
                            x: orientedX, y: orientedY, width: decoded.width, height: decoded.height,
                            orientation: orientation)
                        let from = original.y * decoded.rowStride + original.x * 4
                        let to = (y * fittedSize.width + x) * 4
                        if paintsAlpha {
                            let channels: (Int, Int, Int, Int)
                            if metadata.bitDepth == 16 {
                                let offset = original.y * image.bytesPerRow + original.x * wideLayout.bytesPerPixel
                                channels = try wideLayout.rgba16(wideStorage.advanced(by: offset))
                            } else {
                                channels = (
                                    Int(input[from]) * 257, Int(input[from + 1]) * 257,
                                    Int(input[from + 2]) * 257, Int(input[from + 3]) * 257
                                )
                            }
                            let sample = ReferenceColorAlphaSample.fit(
                                channels, singlePixel: size.width == 1 && size.height == 1,
                                sourceDepth: Int(metadata.bitDepth), vectorLane: x < fittedSize.width / 4 * 4)
                            output[to] = sample.0
                            output[to + 1] = sample.1
                            output[to + 2] = sample.2
                            output[to + 3] = sample.3
                        } else {
                            for channel in 0..<4 { output[to + channel] = input[from + channel] }
                        }
                    }
                }
            }
        }
        try Task.checkCancellation()
        let raster = try ReferenceColorRaster(
            width: fittedSize.width, height: fittedSize.height, rowStride: fittedSize.width * 4, pixels: fitted)
        let displayImage = try ReferenceColorDisplayImage.make(raster: raster, colorSpace: image.colorSpace)
        try Task.checkCancellation()
        return ReferenceColorRasterResult(
            referencePNG: png, referenceSize: size, raster: raster, displayImage: displayImage,
            sourceColorSpace: image.colorSpace)
    }

    /// Qt's aliased painter samples just below exact center boundaries. Its fast
    /// affine fetch advances a truncated 16.16 horizontal step within each row;
    /// vertical coordinates are evaluated afresh for each row. Use integer math
    /// for that bounded grid, without depending on Qt or host floating rounding.
    private static func fittedCoordinate(
        _ position: Int, source: Int, destination: Int, scanline: Bool, palette: Bool, fixedAffine: Bool
    ) -> Int {
        if source == destination { return position }
        if palette {
            // Palette/monochrome transforms use a 12-bit entry-copy grid with
            // truncated steps in both dimensions and no painter boundary bias.
            let step = source * 4096 / destination
            return min(source - 1, (step / 2 + position * step) / 4096)
        }
        let fixedScale = 65_536
        let ratio = Double(source) / Double(destination)
        // Qt's fixed affine path excludes extreme ratios. Its floating fallback
        // evaluates each pixel center independently with the same boundary bias.
        if !fixedAffine {
            let center = (Double(position) + 0.5) * ratio - 1.0 / Double(fixedScale)
            return min(source - 1, max(0, Int(center.rounded(.down))))
        }
        let fixed: Int
        if scanline {
            fixed =
                source * (fixedScale / 2) / destination - 1
                + position * (source * fixedScale / destination)
        } else {
            fixed = (2 * position + 1) * source * (fixedScale / 2) / destination - 1
        }
        return min(source - 1, max(0, fixed / fixedScale))
    }

    private static func originalPoint(x: Int, y: Int, width: Int, height: Int, orientation: Int) -> (x: Int, y: Int) {
        switch orientation {
        case 2: (width - 1 - x, y)
        case 3: (width - 1 - x, height - 1 - y)
        case 4: (x, height - 1 - y)
        case 5: (y, x)
        case 6: (y, height - 1 - x)
        case 7: (width - 1 - y, height - 1 - x)
        case 8: (width - 1 - y, x)
        default: (x, y)
        }
    }
}

/// Profile-compatible immutable display representation of the exact fitted samples used by the planner.
enum ReferenceColorDisplayImage {
    static func make(raster: ReferenceColorRaster, colorSpace: CGColorSpace?) throws -> CGImage {
        try Task.checkCancellation()
        guard let source = colorSpace else { throw ReferenceColorRasterError.unsupportedDisplayProfile }
        let space = source.model == .indexed ? source.baseColorSpace : source
        guard let space else { throw ReferenceColorRasterError.unsupportedDisplayProfile }
        let isGray = space.model == .monochrome && space.numberOfComponents == 1
        guard isGray || (space.model == .rgb && space.numberOfComponents == 3) else {
            throw ReferenceColorRasterError.unsupportedDisplayProfile
        }
        let width = raster.size.width
        let height = raster.size.height
        let bytesPerPixel = isGray ? 2 : 4
        let stride = width * bytesPerPixel
        let pixels: Data
        if !isGray, raster.rowStride == stride {
            pixels = raster.pixels
        } else {
            var packed = Data(count: stride * height)
            try packed.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
                try raster.pixels.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
                    // Raster's validated dimensions/stride prove each source and destination span here.
                    for y in 0..<height {
                        try Task.checkCancellation()
                        for x in 0..<width {
                            let from = y * raster.rowStride + x * 4
                            let to = y * stride + x * bytesPerPixel
                            if isGray {
                                guard input[from] == input[from + 1], input[from] == input[from + 2] else {
                                    throw ReferenceColorRasterError.incompatibleGrayPixels
                                }
                                output[to] = input[from]
                                output[to + 1] = input[from + 3]
                            } else {
                                for channel in 0..<4 { output[to + channel] = input[from + channel] }
                            }
                        }
                    }
                }
            }
            pixels = packed
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: bytesPerPixel * 8,
                bytesPerRow: stride, space: space, bitmapInfo: .init(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw ReferenceColorRasterError.displayImageUnavailable }
        return image
    }
}
