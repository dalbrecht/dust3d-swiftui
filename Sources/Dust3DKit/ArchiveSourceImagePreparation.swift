import Dust3DDocument
import Foundation

enum ArchiveSourceImagePreparation {
    static func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) throws
        -> (models: [SourceMeshBakeImage], legacy: [MeshBakeImage])
    {
        try SourceMeshBakeInput.validate(dataCount: data.count, options: options)
        try ArchiveTextureImagePreparation.validate(limits.textures)
        try ImportedMaterialLoader.validate(dataCount: data.count, options: limits.materials)
        let document = try Dust3DDocument(data: data)
        let references = try document.textureImageReferences()
        // Material inspection already has its own bounded native/Swift copy quotas.
        // Combined encoded admission below precedes every platform pixel decode.
        let materials = try ImportedMaterialLoader.load(data: data, options: limits.materials)
        var remainingEncoded = limits.textures.maximumEncodedTotalBytes
        try ArchiveTextureImagePreparation.preflight(
            references,
            maximumImageBytes: limits.textures.maximumEncodedImageBytes, remainingEncoded: &remainingEncoded)
        for material in materials.models {
            try Task.checkCancellation()
            guard let image = material.image else { continue }
            guard image.bytes.count <= limits.textures.maximumEncodedImageBytes, image.bytes.count <= remainingEncoded
            else { throw ArchiveTextureBakingError.encodedLimitExceeded }
            remainingEncoded -= image.bytes.count
        }
        var remainingDecoded = min(limits.textures.maximumDecodedTotalBytes, options.maximumInputImageBytes)
        let legacy = try ArchiveTextureImagePreparation.decode(
            references, document: document,
            maximumImageBytes: limits.textures.maximumEncodedImageBytes, remainingDecoded: &remainingDecoded)
        var models: [SourceMeshBakeImage] = []
        for material in materials.models {
            try Task.checkCancellation()
            guard let encoded = material.image else { continue }
            guard remainingDecoded > 0 else { throw ArchiveTextureBakingError.decodedLimitExceeded }
            do {
                let decoded = try ImportedImageDecoder.decode(
                    encoded, modelID: material.id,
                    maximumEncodedBytes: limits.textures.maximumEncodedImageBytes, maximumDecodedBytes: remainingDecoded
                )
                remainingDecoded -= decoded.pixels.count
                models.append(SourceMeshBakeImage(decodedImage: decoded))
            } catch is CancellationError { throw CancellationError() } catch {
                throw ArchiveSourceTextureBakingError.importedImageDecoding(modelID: material.id, cause: error)
            }
        }
        try Task.checkCancellation()
        return (models, legacy)
    }
}
