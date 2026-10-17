import Dust3DEngine
import Foundation

/// Caller-decoded image dimensions only. This descriptor does not borrow or decode pixels.
public struct MeshUvImageDescriptor: Sendable {
    public let imageID: String
    public let width: Int
    public let height: Int

    /// Store requested metadata; the loader validates identity, dimensions and duplicate aliases.
    /// - Parameters:
    ///   - imageID: Original engine identity, preserving opaque characters and case.
    ///   - width: Pixel width in 1...8192.
    ///   - height: Pixel height in 1...8192.
    public init(imageID: String, width: Int, height: Int) {
        self.imageID = imageID
        self.width = width
        self.height = height
    }
}

/// Independent copied geometry and triangle-aligned UV metadata, ready to cross actor boundaries.
/// Indexed sharing includes geometry attributes only; metadata corners retain UV seams separately.
public struct MeshWithUvMetadata: Sendable {
    public let geometry: IndexedMesh
    public let metadata: MeshUvMetadata
}

extension MeshLoader {
    /// Load owned geometry and UV metadata without decoding/baking pixels or replacing cached preview behavior.
    /// - Parameters:
    ///   - data: Complete `.ds3` archive bytes.
    ///   - images: At most 10000 caller-resolved image dimensions; missing referenced images reject explicitly.
    ///   - textureSize: Atlas density scale in 1...8192; this is not a baked image size.
    ///   - maximumMetadataPayloadBytes: Native retained metadata quota; zero selects 64 MiB, maximum 256 MiB.
    ///   - maximumIndexedPayloadBytes: Native indexed geometry quota; zero uses the existing default.
    /// - Returns: Copied immutable values, including explicit unknown mappings and original component keys.
    /// - Throws: `MeshLoadingError` preserving native status/cause (including status 5 for successful no-geometry),
    ///   or `CancellationError` at cooperative checks.
    /// Quotas exclude Swift copies, allocator overhead and temporary workspace; native generation is serialized
    /// and cannot be interrupted midway. Unsupported source colors/images do not change the original archive.
    /// - Example: `let output = try MeshLoader.loadWithUvMetadata(data: archive)`.
    public static func loadWithUvMetadata(
        data: Data, images: [MeshUvImageDescriptor] = [], textureSize: Int = 4096,
        maximumMetadataPayloadBytes: Int = 0, maximumIndexedPayloadBytes: Int = 0
    ) throws -> MeshWithUvMetadata {
        try Task.checkCancellation()
        try validateIndexedPayloadBudget(maximumIndexedPayloadBytes)
        guard maximumMetadataPayloadBytes >= 0 else {
            throw MeshLoadingError(status: 1, message: "The UV metadata budget must be zero or positive.")
        }
        guard maximumMetadataPayloadBytes <= Int(DUST3D_MAX_UV_PAYLOAD_BYTES) else {
            throw MeshLoadingError(status: 4, message: "The UV metadata budget exceeds 256 MiB.")
        }
        guard (1...8192).contains(textureSize) else {
            throw MeshLoadingError(status: 1, message: "The UV texture density scale must be in 1...8192.")
        }
        let inputs = try nativeImageDescriptors(images)
        let effectiveBudget =
            maximumMetadataPayloadBytes == 0
            ? Int(DUST3D_DEFAULT_UV_PAYLOAD_BYTES) : maximumMetadataPayloadBytes
        var error = Dust3DError()
        let native = inputs.withUnsafeBufferPointer { descriptors in
            var options = Dust3DUvOptions(
                struct_size: MemoryLayout<Dust3DUvOptions>.size,
                maximum_payload_bytes: maximumMetadataPayloadBytes, texture_size: textureSize,
                images: descriptors.baseAddress, image_count: descriptors.count)
            return data.withUnsafeBytes {
                dust3d_uv_mesh_load($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &options, &error)
            }
        }
        guard let owner = native else { throw loadingError(error) }
        let prepared: (metadata: MeshUvMetadata, indexed: OpaquePointer)
        do {
            defer { dust3d_uv_mesh_destroy(owner) }
            try Task.checkCancellation()
            guard let geometry = dust3d_uv_mesh_geometry(owner) else {
                throw MeshLoadingError(status: 3, message: "The engine returned no UV geometry owner.")
            }
            let metadata = try MeshUvCopy.copy(owner, geometry: geometry, maximumPayloadBytes: effectiveBudget)
            try Task.checkCancellation()
            prepared = (
                metadata, try makeNativeIndexedMesh(from: geometry, maximumPayloadBytes: maximumIndexedPayloadBytes)
            )
        }
        // The UV/expanded owner is gone before allocating Swift vertex/index copies.
        let geometry = try copyAndDestroyIndexedMesh(prepared.indexed)
        try Task.checkCancellation()
        return MeshWithUvMetadata(geometry: geometry, metadata: prepared.metadata)
    }

    private static func nativeImageDescriptors(_ images: [MeshUvImageDescriptor]) throws -> [Dust3DUvImage] {
        guard images.count <= 10000 else {
            throw MeshLoadingError(status: 1, message: "At most 10000 resolved UV image descriptors are supported.")
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
                    status: 1, message: "UV images need unique engine identities and dimensions in 1...8192.")
            }
            var result = Dust3DUvImage()
            withUnsafeMutableBytes(of: &result.image_id) { $0.copyBytes(from: bytes) }
            result.width = image.width
            result.height = image.height
            return result
        }
    }
}
