import Dust3DDocument
import Foundation

/// Logical retained-image quotas; ImageIO/native workspace and archive storage are separate.
public struct ArchiveTextureLimits: Sendable {
    public let maximumEncodedImageBytes: Int
    public let maximumEncodedTotalBytes: Int
    public let maximumDecodedTotalBytes: Int

    /// Set positive quotas, each at most 256 MiB; validated before archive parsing.
    /// - Parameters:
    ///   - maximumEncodedImageBytes: Maximum size of one retained PNG before copying.
    ///   - maximumEncodedTotalBytes: Maximum sum of distinct referenced PNG byte counts.
    ///   - maximumDecodedTotalBytes: Maximum sum of owned RGBA8 inputs before baking.
    public init(
        maximumEncodedImageBytes: Int = 32 * 1024 * 1024,
        maximumEncodedTotalBytes: Int = 128 * 1024 * 1024,
        maximumDecodedTotalBytes: Int = 256 * 1024 * 1024
    ) {
        self.maximumEncodedImageBytes = maximumEncodedImageBytes
        self.maximumEncodedTotalBytes = maximumEncodedTotalBytes
        self.maximumDecodedTotalBytes = maximumDecodedTotalBytes
    }
}

/// Resource failures and per-asset decoder causes; document/native errors propagate unchanged.
public enum ArchiveTextureBakingError: LocalizedError, Equatable, Sendable {
    case invalidLimits
    case encodedLimitExceeded
    case decodedLimitExceeded
    case missingAsset(String)
    case imageDecoding(assetName: String, cause: MeshPNGDecodingError)

    /// Keep the retained asset identity and underlying decoder cause in UI notices.
    public var errorDescription: String? {
        switch self {
        case .invalidLimits: return "The material image resource limits are invalid."
        case .encodedLimitExceeded: return "The encoded material images exceed the configured input limit."
        case .decodedLimitExceeded: return "The decoded material images exceed the configured input limit."
        case .missingAsset(let name): return "The material image asset \(name) is missing from the document."
        case .imageDecoding(let name, let cause):
            return "Could not decode material image \(name): \(cause.localizedDescription)"
        }
    }
}

/// Injectable archive material boundary shared by native app previews.
public protocol ArchiveTextureBaking: Sendable {
    /// Bake a complete archive without changing retained document bytes.
    /// - Parameters:
    ///   - data: Complete archive snapshot.
    ///   - options: Native output dimensions and quotas.
    ///   - limits: Independent retained-image admission quotas.
    /// - Returns: Copied geometry and matching material maps.
    /// - Throws: Original archive, image, native or cancellation errors.
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
}

/// Shared archive-to-baker infrastructure, isolated from observable UI state.
public actor ArchiveTextureBakingService: ArchiveTextureBaking {
    private let baker = MeshBakingService()

    /// Create a background service for the standalone viewer or editor.
    public init() {}

    /// Resolve and decode only referenced color assets, then invoke the owned native baker.
    /// - Parameters:
    ///   - data: Complete lossless archive, never rewritten by this operation.
    ///   - options: Native map dimensions and output quotas.
    ///   - limits: Independent encoded and aggregate decoded input quotas.
    /// - Returns: Owned Swift mesh, UVs, tangent frames and baked maps.
    /// - Throws: `ArchiveTextureBakingError`, document errors, native `MeshLoadingError`
    ///   or `CancellationError`. Asset failures retain the original decoder cause.
    /// - Note: Cancellation is cooperative; ImageIO and inherited generation cannot be preempted.
    /// - Example: `let mesh = try await ArchiveTextureBakingService().load(data: archive)`.
    public func load(
        data: Data, options: MeshBakeOptions = MeshBakeOptions(), limits: ArchiveTextureLimits = ArchiveTextureLimits()
    ) async throws -> MeshWithBakedTextures {
        try Task.checkCancellation()
        let ceiling = 256 * 1024 * 1024
        guard
            [limits.maximumEncodedImageBytes, limits.maximumEncodedTotalBytes, limits.maximumDecodedTotalBytes]
                .allSatisfy({ (1...ceiling).contains($0) })
        else { throw ArchiveTextureBakingError.invalidLimits }
        let document = try Dust3DDocument(data: data)
        let references = try document.textureImageReferences()
        var remainingEncoded = limits.maximumEncodedTotalBytes
        for reference in references {
            guard reference.encodedByteCount <= limits.maximumEncodedImageBytes,
                reference.encodedByteCount <= remainingEncoded
            else { throw ArchiveTextureBakingError.encodedLimitExceeded }
            remainingEncoded -= reference.encodedByteCount
        }
        var remainingDecoded = limits.maximumDecodedTotalBytes
        var images: [MeshBakeImage] = []
        for reference in references {
            try Task.checkCancellation()
            guard remainingDecoded > 0 else { throw ArchiveTextureBakingError.decodedLimitExceeded }
            guard let encoded = document.asset(named: reference.assetName) else {
                throw ArchiveTextureBakingError.missingAsset(reference.assetName)
            }
            do {
                let image = try MeshPNGDecoder.decode(
                    encoded, imageID: reference.imageID,
                    maximumEncodedBytes: limits.maximumEncodedImageBytes, maximumDecodedBytes: remainingDecoded)
                remainingDecoded -= image.pixels.count
                images.append(image)
            } catch let cause as MeshPNGDecodingError {
                throw ArchiveTextureBakingError.imageDecoding(assetName: reference.assetName, cause: cause)
            }
        }
        try Task.checkCancellation()
        return try await baker.load(data: data, images: images, options: options)
    }
}
