import CoreGraphics
import Dust3DDocument
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ReferenceImageError: Error, Equatable, Sendable {
    case invalidImage
    case unsupportedFormat
    case imageTooLarge
    case conversionFailed
    case fileReadFailed(String)
}

/// Bounded platform raster boundary; callers run these synchronous ImageIO operations away from the UI actor.
enum ReferenceImageCodec {
    static let maximumEncodedBytes = 32 * 1024 * 1024

    static func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= 8192, height <= 8192,
            width <= 16 * 1024 * 1024 / height
        else { throw ReferenceImageError.imageTooLarge }
    }

    static func importPNG(_ data: Data) throws -> Data {
        let image = try decode(data, pngOnly: false)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else {
            throw ReferenceImageError.conversionFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ReferenceImageError.conversionFailed }
        guard output.length <= maximumEncodedBytes else { throw ReferenceImageError.imageTooLarge }
        return output as Data
    }

    static func decodePNG(_ data: Data) throws -> CGImage { try decode(data, pngOnly: true) }

    private static func decode(_ data: Data, pngOnly: Bool) throws -> CGImage {
        guard data.count <= maximumEncodedBytes else { throw ReferenceImageError.imageTooLarge }
        guard !data.isEmpty,
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(source) > 0,
            let sourceType = CGImageSourceGetType(source)
        else { throw ReferenceImageError.invalidImage }
        let allowed = pngOnly ? [UTType.png] : [.png, .jpeg, .bmp, .gif, .tiff]
        guard allowed.contains(where: { $0.identifier == sourceType as String }) else {
            throw ReferenceImageError.unsupportedFormat
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { throw ReferenceImageError.invalidImage }
        try validateDimensions(width: width.intValue, height: height.intValue)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else { throw ReferenceImageError.invalidImage }
        try validateDimensions(width: image.width, height: image.height)
        return image
    }
}

struct ReferenceImagePreview: Sendable {
    let image: CGImage?
    let changed: Bool
}

/// Asynchronous raster boundary, injectable so completion ordering can be verified deterministically.
protocol ReferenceImageServing: Sendable {
    func importImage(url: URL) async throws -> Data
    func preview(document: Dust3DDocument) async throws -> ReferenceImagePreview
}

/// One window's off-main raster decoding/cache. Model-only edits do not call this service.
actor ReferenceImageService: ReferenceImageServing {
    private var cachedPNG: Data?
    private var cachedImage: CGImage?

    func importImage(url: URL) throws -> Data {
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard properties.isRegularFile == true else { throw ReferenceImageError.invalidImage }
            guard let size = properties.fileSize, size <= ReferenceImageCodec.maximumEncodedBytes else {
                throw ReferenceImageError.imageTooLarge
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var buffer = Data()
            // Bound the read even if the file grows after its metadata was checked.
            while buffer.count <= ReferenceImageCodec.maximumEncodedBytes {
                try Task.checkCancellation()
                let remaining = ReferenceImageCodec.maximumEncodedBytes + 1 - buffer.count
                let chunk = try handle.read(upToCount: min(64 * 1024, remaining)) ?? Data()
                if chunk.isEmpty { break }
                buffer.append(chunk)
            }
            data = buffer
        } catch let error as ReferenceImageError {
            throw error
        } catch {
            throw ReferenceImageError.fileReadFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        let result = try ReferenceImageCodec.importPNG(data)
        try Task.checkCancellation()
        return result
    }

    func preview(document: Dust3DDocument) throws -> ReferenceImagePreview {
        try Task.checkCancellation()
        if let count = document.referenceImageByteCount, count > ReferenceImageCodec.maximumEncodedBytes {
            throw ReferenceImageError.imageTooLarge
        }
        guard let png = document.referenceImagePNG else {
            let changed = cachedPNG != nil
            cachedPNG = nil
            cachedImage = nil
            return .init(image: nil, changed: changed)
        }
        if png == cachedPNG, let cachedImage { return .init(image: cachedImage, changed: false) }
        let image = try ReferenceImageCodec.decodePNG(png)
        try Task.checkCancellation()
        cachedPNG = png
        cachedImage = image
        return .init(image: image, changed: true)
    }
}
