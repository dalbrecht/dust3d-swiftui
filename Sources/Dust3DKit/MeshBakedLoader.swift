import Dust3DEngine
import Foundation

extension MeshLoader {
    /// Generate expanded textured geometry and copy every borrowed native output.
    /// This synchronous entry point performs CPU work; call it from a background
    /// actor/task. Existing indexed geometry sharing is deliberately not reused.
    /// - Parameters:
    ///   - data: Complete `.ds3` archive, at most 256 MiB.
    ///   - images: At most 10000 decoded straight-alpha RGBA8 views with unique identities.
    ///   - options: Map dimensions and independent logical resource quotas.
    /// - Returns: Swift-owned geometry, UVs, tangent frames and map bytes.
    /// - Throws: `MeshLoadingError` preserving native status/cause, or `CancellationError`
    ///   at Swift cooperative checks. Quotas exclude Swift copies and workspace.
    /// - Example: `let result = try MeshLoader.loadBaked(data: archive, options: options)`.
    public static func loadBaked(
        data: Data, images: [MeshBakeImage] = [], options: MeshBakeOptions = MeshBakeOptions()
    ) throws -> MeshWithBakedTextures {
        try loadBaked(data: data, images: images, options: options, cancellation: nil)
    }

    static func loadBaked(
        data: Data, images: [MeshBakeImage], options: MeshBakeOptions, cancellation: OpaquePointer?
    ) throws -> MeshWithBakedTextures {
        try Task.checkCancellation()
        try MeshBakedInput.validate(dataCount: data.count, options: options)
        // NSData's immutable bytes stay pinned for the synchronous native call.
        // Avoid retaining pointers obtained from a completed Data.withUnsafeBytes scope.
        var inputs = try MeshBakedInput.descriptors(images)
        let storage = images.map { $0.pixels as NSData }
        for index in inputs.indices {
            inputs[index].pixels = storage[index].bytes.assumingMemoryBound(to: UInt8.self)
        }
        var error = Dust3DError()
        let owner = withExtendedLifetime(storage) {
            inputs.withUnsafeBufferPointer { descriptors in
                var native = Dust3DBakeOptions()
                native.struct_size = MemoryLayout<Dust3DBakeOptions>.size
                native.color_size = options.colorSize
                native.normal_size = options.normalSize
                native.material_size = options.materialSize
                native.atlas_texture_size = options.atlasTextureSize
                native.maximum_uv_payload_bytes = options.maximumMetadataPayloadBytes
                native.maximum_bake_payload_bytes = options.maximumBakePayloadBytes
                native.maximum_spatial_grid_entries = options.maximumSpatialGridEntries
                native.images = descriptors.baseAddress
                native.image_count = descriptors.count
                native.cancellation = cancellation
                return data.withUnsafeBytes {
                    dust3d_baked_mesh_load($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &native, &error)
                }
            }
        }
        guard let owner else { throw loadingError(error) }
        defer { dust3d_baked_mesh_destroy(owner) }
        try Task.checkCancellation()
        return try MeshBakedCopy.copy(owner, options: options)
    }
}

enum MeshBakedInput {
    static func validate(dataCount: Int, options: MeshBakeOptions) throws {
        guard dataCount <= MeshLoader.maximumFileSize else {
            throw MeshLoadingError(status: 4, message: "The baked mesh archive exceeds 256 MiB.")
        }
        guard
            [options.colorSize, options.normalSize, options.materialSize, options.atlasTextureSize]
                .allSatisfy({ (1...8192).contains($0) })
        else { throw MeshLoadingError(status: 1, message: "Bake dimensions must be in 1...8192.") }
        let quotas = [options.maximumMetadataPayloadBytes, options.maximumBakePayloadBytes]
        guard quotas.allSatisfy({ $0 >= 0 }) else {
            throw MeshLoadingError(status: 1, message: "Bake payload budgets must be zero or positive.")
        }
        guard quotas.allSatisfy({ $0 <= 256 * 1024 * 1024 }) else {
            throw MeshLoadingError(status: 4, message: "Bake payload budgets must not exceed 256 MiB.")
        }
        guard (0...16_000_000).contains(options.maximumSpatialGridEntries) else {
            throw MeshLoadingError(status: 1, message: "The fold spatial grid limit must be in 0...16000000.")
        }
    }

    static func descriptors(_ images: [MeshBakeImage]) throws -> [Dust3DBakeImage] {
        guard images.count <= 10000 else {
            throw MeshLoadingError(status: 1, message: "Baking accepts at most 10000 decoded image views.")
        }
        var identities: Set<[UInt8]> = []
        return try images.map { image in
            try Task.checkCancellation()
            let bytes = Array(image.imageID.utf8)
            var identity = bytes
            if identity.count == 38, identity.first == 123, identity.last == 125 {
                identity = Array(identity.dropFirst().dropLast())
            }
            guard identity.count == 36, !identity.contains(0),
                [8, 13, 18, 23].allSatisfy({ identity[$0] == 45 }), identities.insert(identity).inserted,
                (1...8192).contains(image.width), (1...8192).contains(image.height)
            else {
                throw MeshLoadingError(
                    status: 1, message: "Bake images require unique engine identities and dimensions in 1...8192.")
            }
            let rowBytes = image.width * 4
            guard image.rowStride >= rowBytes, image.pixels.count >= rowBytes,
                image.height == 1 || image.rowStride <= (image.pixels.count - rowBytes) / (image.height - 1)
            else {
                throw MeshLoadingError(
                    status: 1, message: "A bake image stride/span does not cover its readable RGBA8 rows.")
            }
            var native = Dust3DBakeImage()
            withUnsafeMutableBytes(of: &native.image_id) { $0.copyBytes(from: bytes) }
            native.width = image.width
            native.height = image.height
            native.row_stride = image.rowStride
            native.byte_count = image.pixels.count
            return native
        }
    }
}
