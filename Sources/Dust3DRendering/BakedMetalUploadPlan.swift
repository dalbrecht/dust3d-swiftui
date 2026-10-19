import Dust3DKit
import Foundation
import Metal

/// Preflight and allocation failures preserve the specific resource or policy boundary.
enum BakedMetalPreparationError: LocalizedError, Equatable {
    case invalidLimits
    case invalidTexture(String)
    case payloadLimitExceeded
    case invalidCamera
    case drawLimitExceeded
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidLimits: return "The material renderer resource limits are invalid."
        case .invalidTexture(let name): return "The \(name) material texture has invalid dimensions or pixel storage."
        case .payloadLimitExceeded: return "The material preview exceeds its combined GPU payload limit."
        case .invalidCamera: return "The material preview camera contains invalid values."
        case .drawLimitExceeded: return "The material preview exceeds 4096 policy draw batches per pass."
        case .unavailable(let cause): return cause
        }
    }
}

/// A validated CPU view; source padding is separate from tightly allocated GPU payload.
struct BakedMetalImage: Sendable {
    let width: Int
    let height: Int
    let rowStride: Int
    let pixels: Data
    let pixelFormat: MTLPixelFormat

    var payloadBytes: Int { width * height * 4 }

    init(source: MeshTextureImage, name: String, pixelFormat: MTLPixelFormat) throws {
        guard (1...8192).contains(source.width), (1...8192).contains(source.height),
            source.rowStride >= source.width * 4, source.rowStride <= 256 * 1024 * 1024,
            source.rowStride.isMultiple(of: 4)
        else { throw BakedMetalPreparationError.invalidTexture(name) }
        let precedingRows = source.rowStride.multipliedReportingOverflow(by: source.height - 1)
        let span = precedingRows.partialValue.addingReportingOverflow(source.width * 4)
        guard !precedingRows.overflow, !span.overflow, span.partialValue <= source.pixels.count else {
            throw BakedMetalPreparationError.invalidTexture(name)
        }
        width = source.width
        height = source.height
        rowStride = source.rowStride
        pixels = source.pixels
        self.pixelFormat = pixelFormat
    }

    init(defaultPixel: [UInt8], pixelFormat: MTLPixelFormat) {
        width = 1
        height = 1
        rowStride = 4
        pixels = Data(defaultPixel)
        self.pixelFormat = pixelFormat
    }

    /// Conservative atlas-wide routing avoids sampling unknown alpha as opaque.
    func containsTransparency() throws -> Bool {
        try pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for row in 0..<height {
                try Task.checkCancellation()
                for column in 0..<width where bytes[row * rowStride + column * 4 + 3] < 255 { return true }
            }
            return false
        }
    }
}

/// Resource admission precedes Metal calls. Quotas exclude CPU source/workspace,
/// device allocation overhead and in-flight replacement buffers; no hard RSS claim.
struct BakedMetalUploadPlan: Sendable {
    let images: [BakedMetalImage]
    let payloadBytes: Int
    let normalMapEnabled: Bool
    let hasTransparentColor: Bool

    init(
        geometry: TexturedRenderGeometry, maximumBufferLength: Int,
        maximumPayloadBytes: Int = 256 * 1024 * 1024
    ) throws {
        try Task.checkCancellation()
        guard (1...256 * 1024 * 1024).contains(maximumPayloadBytes) else {
            throw BakedMetalPreparationError.invalidLimits
        }
        try geometry.validateBufferLengths(maximumBufferLength: maximumBufferLength)
        var remaining = maximumPayloadBytes
        for (count, stride) in [
            (geometry.vertices.count, MemoryLayout<TexturedRenderGeometry.Vertex>.stride),
            (geometry.indices.count, MemoryLayout<UInt32>.stride),
        ] {
            guard count <= remaining / stride else { throw BakedMetalPreparationError.payloadLimitExceeded }
            remaining -= count * stride
        }
        let maps = geometry.textures
        let color = try BakedMetalImage(source: maps.color, name: "color", pixelFormat: .rgba8Unorm_srgb)
        let optional: [(MeshTextureImage?, String, MTLPixelFormat, [UInt8])] = [
            (maps.normal, "normal", .rgba8Unorm, [128, 128, 255, 255]),
            (maps.metallic, "metallic", .rgba8Unorm, [0, 0, 0, 255]),
            (maps.roughness, "roughness", .rgba8Unorm, [255, 255, 255, 255]),
            (maps.emissive, "emissive", .rgba8Unorm_srgb, [0, 0, 0, 255]),
        ]
        var images = [color]
        for (source, name, format, fallback) in optional {
            images.append(
                try source.map { try BakedMetalImage(source: $0, name: name, pixelFormat: format) }
                    ?? BakedMetalImage(defaultPixel: fallback, pixelFormat: format))
        }
        for image in images {
            guard image.payloadBytes <= remaining else { throw BakedMetalPreparationError.payloadLimitExceeded }
            remaining -= image.payloadBytes
        }
        self.images = images
        payloadBytes = maximumPayloadBytes - remaining
        normalMapEnabled = maps.normal != nil
        hasTransparentColor = try color.containsTransparency()
    }
}
