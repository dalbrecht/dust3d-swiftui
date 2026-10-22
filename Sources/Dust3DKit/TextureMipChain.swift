import Foundation

/// Specific owned mip-chain validation failures; no native pointer escapes validation.
public enum TextureMipChainError: LocalizedError, Sendable, Equatable {
    case invalidLevelCount, invalidImage, invalidDimensions, invalidSamplingLod

    public var errorDescription: String? {
        switch self {
        case .invalidLevelCount: "A texture mip chain has an invalid number of levels."
        case .invalidImage: "A texture mip level has invalid dimensions, row stride or pixel storage."
        case .invalidDimensions: "Texture mip dimensions must halve at each level and stop at one pixel."
        case .invalidSamplingLod: "The texture sampling LOD exceeds its retained mip levels."
        }
    }
}

/// Immutable Swift-owned RGBA8 levels, including the base. No filtering or color conversion occurs.
public struct TextureMipChain: Sendable, Equatable {
    public let levels: [MeshTextureImage]
    /// Highest safe sampling LOD, independently constrained by retained level availability.
    public let maximumSamplingLod: Double

    /// Validate an owned chain without inferring chart safety from image dimensions.
    /// - Parameters:
    ///   - levels: Base followed by at most thirteen additional levels, each dimension halved with a floor of one.
    ///   - maximumSamplingLod: Finite nonnegative cap supplied by the chart-aware producer.
    /// - Throws: TextureMipChainError for inconsistent images, level order/count or unavailable sampling levels.
    /// - Example: `let chain = try TextureMipChain(levels: images, maximumSamplingLod: 2)`.
    public init(levels: [MeshTextureImage], maximumSamplingLod: Double) throws {
        guard (1...14).contains(levels.count) else { throw TextureMipChainError.invalidLevelCount }
        var previous: MeshTextureImage?
        for image in levels {
            try Self.validateImage(
                width: image.width, height: image.height, stride: image.rowStride, bytes: image.pixels.count)
            try Self.validateDimensions(width: image.width, height: image.height, previous: previous)
            previous = image
        }
        try Self.validateLod(maximumSamplingLod, count: levels.count)
        self.levels = levels
        self.maximumSamplingLod = maximumSamplingLod
    }

    static func validateImage(width: Int, height: Int, stride: Int, bytes: Int) throws {
        guard (1...8192).contains(width), (1...8192).contains(height), stride == width * 4,
            bytes == stride * height
        else { throw TextureMipChainError.invalidImage }
    }

    static func validateDimensions(width: Int, height: Int, previous: MeshTextureImage?) throws {
        guard let previous else { return }
        guard previous.width > 1 || previous.height > 1,
            width == max(1, previous.width / 2), height == max(1, previous.height / 2)
        else { throw TextureMipChainError.invalidDimensions }
    }

    static func validateLod(_ value: Double, count: Int) throws {
        guard value.isFinite, value >= 0, value <= Double(count - 1) else {
            throw TextureMipChainError.invalidSamplingLod
        }
    }
}
