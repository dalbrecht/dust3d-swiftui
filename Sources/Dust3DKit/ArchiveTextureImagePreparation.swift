import Dust3DDocument
import Foundation

/// Shared admission/decoding for retained procedural PNGs. No document writes occur here.
enum ArchiveTextureImagePreparation {
    static func validate(_ limits: ArchiveTextureLimits) throws {
        let ceiling = 256 * 1024 * 1024
        guard
            [limits.maximumEncodedImageBytes, limits.maximumEncodedTotalBytes, limits.maximumDecodedTotalBytes]
                .allSatisfy({ (1...ceiling).contains($0) })
        else { throw ArchiveTextureBakingError.invalidLimits }
    }

    static func preflight(
        _ references: [DocumentTextureImageReference], maximumImageBytes: Int,
        remainingEncoded: inout Int
    ) throws {
        for reference in references {
            try Task.checkCancellation()
            guard reference.encodedByteCount <= maximumImageBytes,
                reference.encodedByteCount <= remainingEncoded
            else { throw ArchiveTextureBakingError.encodedLimitExceeded }
            remainingEncoded -= reference.encodedByteCount
        }
    }

    static func decode(
        _ references: [DocumentTextureImageReference], document: Dust3DDocument,
        maximumImageBytes: Int, remainingDecoded: inout Int
    ) throws -> [MeshBakeImage] {
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
                    maximumEncodedBytes: maximumImageBytes, maximumDecodedBytes: remainingDecoded)
                remainingDecoded -= image.pixels.count
                images.append(image)
            } catch let cause as MeshPNGDecodingError {
                throw ArchiveTextureBakingError.imageDecoding(assetName: reference.assetName, cause: cause)
            }
        }
        return images
    }
}
