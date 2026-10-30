import Dust3DEngine
import Foundation

extension MeshLoader {
    /// Bake imported and procedural surfaces into independently owned output.
    /// This synchronous CPU entry point belongs on a background actor/task.
    /// - Parameters:
    ///   - data: Complete `.ds3` bytes, at most 256 MiB.
    ///   - modelImages: Source-matched imported-model decoded images, without factors applied.
    ///   - images: Decoded procedural component images, keyed by engine identity.
    ///   - options: Dimensions and independent retained-data quotas.
    /// - Returns: Copied geometry, material policy, packed UVs and textures with a sampling LOD clamp.
    /// - Throws: SourceMeshBakeError, MeshLoadingError preserving native cause, or CancellationError.
    /// - Example: `let result = try MeshLoader.loadSourceBaked(data: archive, modelImages: decoded)`.
    public static func loadSourceBaked(
        data: Data, modelImages: [SourceMeshBakeImage] = [], images: [MeshBakeImage] = [],
        options: SourceMeshBakeOptions = SourceMeshBakeOptions()
    ) throws -> SourceBakedMesh {
        try loadSourceBaked(data: data, modelImages: modelImages, images: images, options: options, cancellation: nil)
    }

    static func loadSourceBaked(
        data: Data, modelImages: [SourceMeshBakeImage], images: [MeshBakeImage],
        options: SourceMeshBakeOptions, cancellation: OpaquePointer?
    ) throws -> SourceBakedMesh {
        try Task.checkCancellation()
        try SourceMeshBakeInput.validate(dataCount: data.count, options: options)
        try SourceMeshBakeInput.validateImages(
            modelImages, legacy: images, maximumBytes: options.maximumInputImageBytes)
        var legacy = try MeshBakedInput.descriptors(images)
        // Immutable NSData pins all pixel/identity pointers until the synchronous C call ends.
        let legacyPixels = images.map { $0.pixels as NSData }
        let modelPixels = modelImages.map { $0.pixels as NSData }
        let identities = modelImages.map { Data($0.modelID.utf8) as NSData }
        for index in legacy.indices {
            legacy[index].pixels = legacyPixels[index].bytes.assumingMemoryBound(to: UInt8.self)
        }
        let models = modelImages.enumerated().map { index, image in
            var value = Dust3DModelBakeImage()
            value.model_id = identities[index].bytes.assumingMemoryBound(to: CChar.self)
            value.model_id_length = identities[index].length
            value.image.width = image.width
            value.image.height = image.height
            value.image.row_stride = image.rowStride
            value.image.byte_count = image.pixels.count
            value.image.pixels = modelPixels[index].bytes.assumingMemoryBound(to: UInt8.self)
            return value
        }
        var error = Dust3DError()
        let owner = withExtendedLifetime((legacyPixels, modelPixels, identities)) {
            legacy.withUnsafeBufferPointer { legacyViews in
                models.withUnsafeBufferPointer { modelViews in
                    var native = SourceMeshBakeInput.native(options, cancellation: cancellation)
                    native.legacy.images = legacyViews.baseAddress
                    native.legacy.image_count = legacyViews.count
                    native.model_images = modelViews.baseAddress
                    native.model_image_count = modelViews.count
                    return data.withUnsafeBytes {
                        let bytes = $0.bindMemory(to: UInt8.self).baseAddress
                        if options.maximumMipLevels == 0 {
                            return dust3d_source_baked_mesh_load(bytes, $0.count, &native, &error)
                        }
                        var mip = Dust3DSourceBakeMipOptions()
                        mip.struct_size = MemoryLayout<Dust3DSourceBakeMipOptions>.size
                        mip.source = native
                        mip.maximum_levels = options.maximumMipLevels
                        return dust3d_source_baked_mesh_load_with_mips(bytes, $0.count, &mip, &error)
                    }
                }
            }
        }
        guard let owner else { throw loadingError(error) }
        defer { dust3d_source_baked_mesh_destroy(owner) }
        try Task.checkCancellation()
        return try SourceBakedCopy.copy(owner, options: options)
    }
}
