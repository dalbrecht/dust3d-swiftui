import CoreGraphics
import Foundation

/// File-preview input and platform resource failures, separate from document errors.
public enum FilePreviewError: LocalizedError, Equatable, Sendable {
    case invalidDimensions
    case invalidPixelStorage
    case unavailable(String)

    /// Specific cause suitable for the system preview error callback.
    public var errorDescription: String? {
        switch self {
        case .invalidDimensions: return "The requested file preview dimensions or scale are invalid."
        case .invalidPixelStorage: return "The file preview pixel storage is incomplete or exceeds its limit."
        case .unavailable(let cause): return cause
        }
    }
}

/// Request arithmetic remains independent of a display server or Metal device.
struct FilePreviewDimensions: Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let pointSize: CGSize
    var rowStride: Int { pixelWidth * 4 }

    init(maximumSize: CGSize, scale: CGFloat) throws {
        guard maximumSize.width.isFinite, maximumSize.height.isFinite,
            maximumSize.width > 0, maximumSize.height > 0,
            scale.isFinite, scale > 0, scale <= 8
        else { throw FilePreviewError.invalidDimensions }
        let largest = max(maximumSize.width, maximumSize.height)
        let factor = min(scale, 2048 / largest)
        let width = max(1, min(2048, ceil(maximumSize.width * factor)))
        let height = max(1, min(2048, ceil(maximumSize.height * factor)))
        let pointScale = min(1 / scale, min(maximumSize.width / width, maximumSize.height / height))
        let points = CGSize(width: width * pointScale, height: height * pointScale)
        guard points.width.isFinite, points.height.isFinite else { throw FilePreviewError.invalidDimensions }
        pixelWidth = Int(width)
        pixelHeight = Int(height)
        pointSize = points
    }
}

/// Owned, tightly packed BGRA8 samples in sRGB, with encoded channels premultiplied by alpha.
/// This representation can cross actors without retaining a Metal buffer or texture.
public struct FilePreviewImage: Sendable {
    public let width: Int
    public let height: Int
    public let rowStride: Int
    public let pointSize: CGSize
    public let pixels: Data

    init(
        gpuPixels: Data, dimensions: FilePreviewDimensions, isSRGBRenderTarget: Bool,
        sourceRowStride: Int? = nil
    ) throws {
        let stride = sourceRowStride ?? dimensions.rowStride
        let precedingRows = stride.multipliedReportingOverflow(by: dimensions.pixelHeight - 1)
        let span = precedingRows.partialValue.addingReportingOverflow(dimensions.rowStride)
        guard stride >= dimensions.rowStride, !precedingRows.overflow, !span.overflow,
            span.partialValue <= gpuPixels.count, gpuPixels.count <= 32 * 1024 * 1024
        else { throw FilePreviewError.invalidPixelStorage }
        let width = dimensions.pixelWidth
        let height = dimensions.pixelHeight
        let rowStride = dimensions.rowStride
        var result = Data(count: rowStride * height)
        try result.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            try gpuPixels.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
                for row in 0..<height {
                    try Task.checkCancellation()
                    for column in 0..<width {
                        let source = row * stride + column * 4
                        let target = row * rowStride + column * 4
                        let alpha = input[source + 3]
                        output[target + 3] = alpha
                        for channel in 0..<3 {
                            if alpha == 0 {
                                output[target + channel] = 0
                            } else if alpha == 255 || !isSRGBRenderTarget {
                                output[target + channel] = input[source + channel]
                            } else {
                                // Metal blends linear light before attachment encoding; Core Graphics
                                // expects premultiplication after encoding. Avoid bright thumbnail halos.
                                let encoded = Double(input[source + channel]) / 255
                                let linear = encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
                                let opacity = Double(alpha) / 255
                                let straight = min(1, max(0, linear / opacity))
                                let color =
                                    straight <= 0.0031308 ? 12.92 * straight : 1.055 * pow(straight, 1 / 2.4) - 0.055
                                output[target + channel] = UInt8(
                                    min(Double(alpha), max(0, (color * Double(alpha)).rounded())))
                            }
                        }
                    }
                }
            }
        }
        self.width = width
        self.height = height
        self.rowStride = rowStride
        pointSize = dimensions.pointSize
        pixels = result
    }

    /// Create a drawing callback that system preview workers may invoke on any executor.
    /// - Returns: A nonisolated Sendable drawing block retaining only immutable image data and size.
    /// - Throws: `FilePreviewError.unavailable` if Core Graphics cannot create the image.
    public nonisolated func makeDrawing() throws -> @Sendable (CGContext) -> Bool {
        let image = try makeCGImage()
        return { context in
            // Quick Look's Core Graphics callback uses its scaled bitmap coordinates.
            // The clip bounds also respect a caller-supplied coordinate transform.
            context.draw(image, in: context.boundingBoxOfClipPath)
            return true
        }
    }

    /// Create a Core Graphics image retaining the owned samples with explicit sRGB semantics.
    /// - Returns: Image with encoded-premultiplied alpha and the rendered pixel dimensions.
    /// - Throws: `FilePreviewError.unavailable` if the platform cannot create image resources.
    public func makeCGImage() throws -> CGImage {
        guard let provider = CGDataProvider(data: pixels as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowStride,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(
                    .byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw FilePreviewError.unavailable("Core Graphics could not create the rendered file preview image.") }
        return image
    }
}
