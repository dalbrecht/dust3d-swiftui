import CoreGraphics
import Dust3DDocument
import Dust3DKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ColorImageError: Error, Equatable, LocalizedError {
    case invalidRetainedAsset
    case invalidFile
    case invalidImage
    case unsupportedFormat
    case imageTooLarge
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .invalidRetainedAsset: "The retained image resource changed or cannot be assigned."
        case .invalidFile: "Choose a regular image file on this Mac."
        case .invalidImage: "The image could not be fully decoded."
        case .unsupportedFormat: "Choose a PNG, JPEG, BMP, GIF or TIFF image."
        case .imageTooLarge: "The image exceeds the 32 MiB encoded or 8192-pixel image limits."
        case .conversionFailed: "The image could not be converted to PNG."
        }
    }
}

struct ColorImageReadError: Error, LocalizedError {
    let fileName: String
    let cause: any Error
    var errorDescription: String? { "Could not read \(fileName): \(cause.localizedDescription)" }
}

struct ColorImagePreparationError: Error, LocalizedError {
    let fileName: String
    let cause: any Error
    var errorDescription: String? { "Could not prepare \(fileName): \(cause.localizedDescription)" }
}

/// Material images retain encoded pixel orientation. Existing PNG bytes are never re-encoded.
/// Limits cover encoded input and logical pixel storage, not ImageIO's workspace or total RSS.
enum ColorImageCodec {
    static let maximumEncodedBytes = 32 * 1024 * 1024
    static let maximumDecodedBytes = 256 * 1024 * 1024

    static func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= 8192, height <= 8192,
            width <= maximumDecodedBytes / 4 / height
        else { throw ColorImageError.imageTooLarge }
    }

    static func validatePNG(_ data: Data) throws {
        _ = try MeshPNGDecoder.decode(data, imageID: "import-validation")
    }

    static func prepare(_ data: Data) throws -> Data {
        try Task.checkCancellation()
        guard data.count <= maximumEncodedBytes else { throw ColorImageError.imageTooLarge }
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, options),
            CGImageSourceGetCount(source) > 0, let sourceType = CGImageSourceGetType(source)
        else { throw ColorImageError.invalidImage }
        guard [UTType.png, .jpeg, .bmp, .gif, .tiff].contains(where: { $0.identifier == sourceType as String })
        else { throw ColorImageError.unsupportedFormat }
        if sourceType as String == UTType.png.identifier {
            try validatePNG(data)
            try Task.checkCancellation()
            return data
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { throw ColorImageError.invalidImage }
        try validateDimensions(width: width.intValue, height: height.intValue)
        try Task.checkCancellation()
        // Use the first encoded frame without a display-orientation transform, as the baking decoder does.
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options),
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else { throw ColorImageError.invalidImage }
        try validateDimensions(width: image.width, height: image.height)
        guard image.bytesPerRow <= maximumDecodedBytes / image.height else { throw ColorImageError.imageTooLarge }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { throw ColorImageError.conversionFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ColorImageError.conversionFailed }
        guard output.length <= maximumEncodedBytes else { throw ColorImageError.imageTooLarge }
        let png = output as Data
        try validatePNG(png)
        try Task.checkCancellation()
        return png
    }
}

protocol ColorImageServing: Sendable {
    func importImage(url: URL) async throws -> Data
    func validateRetainedImage(document: Dust3DDocument, asset: DocumentColorImageAsset) async throws
}

/// Off-main bounded raster boundary. Cancellation never publishes a partially prepared image.
actor ColorImageService: ColorImageServing {
    func validateRetainedImage(document: Dust3DDocument, asset: DocumentColorImageAsset) throws {
        try Task.checkCancellation()
        guard asset.canAssign, document.colorImageAssets().contains(asset) else {
            if let issue = asset.issue { throw issue }
            throw ColorImageError.invalidRetainedAsset
        }
        guard asset.encodedByteCount <= ColorImageCodec.maximumEncodedBytes else {
            throw ColorImageError.imageTooLarge
        }
        guard let data = document.asset(named: asset.assetName) else { throw ColorImageError.invalidRetainedAsset }
        do {
            try ColorImageCodec.validatePNG(data)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ColorImagePreparationError(fileName: asset.assetName, cause: error)
        }
    }

    func importImage(url: URL) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL else { throw ColorImageError.invalidFile }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard properties.isRegularFile == true else { throw ColorImageError.invalidFile }
            guard let size = properties.fileSize, size >= 0, size <= ColorImageCodec.maximumEncodedBytes
            else { throw ColorImageError.imageTooLarge }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var buffer = Data()
            while buffer.count <= ColorImageCodec.maximumEncodedBytes {
                try Task.checkCancellation()
                let remaining = ColorImageCodec.maximumEncodedBytes + 1 - buffer.count
                let chunk = try handle.read(upToCount: min(64 * 1024, remaining)) ?? Data()
                if chunk.isEmpty { break }
                buffer.append(chunk)
            }
            data = buffer
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ColorImageError {
            throw error
        } catch {
            throw ColorImageReadError(fileName: url.lastPathComponent, cause: error)
        }
        do {
            return try ColorImageCodec.prepare(data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ColorImagePreparationError(fileName: url.lastPathComponent, cause: error)
        }
    }
}
