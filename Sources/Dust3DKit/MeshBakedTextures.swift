import Foundation

/// Immutable straight-alpha RGBA8 image. Color/emission retain source encoding;
/// normal and scalar maps contain linear data. All bytes belong to Swift.
public struct MeshTextureImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let rowStride: Int
    public let pixels: Data
}

/// Copied optional maps; color is always present on successful baking.
public struct MeshTextureMaps: Sendable {
    public let color: MeshTextureImage
    public let normal: MeshTextureImage?
    public let metallic: MeshTextureImage?
    public let roughness: MeshTextureImage?
    public let emissive: MeshTextureImage?
}

/// Copied original-triangle tangent frame. Missing mappings remain explicit.
public struct MeshTextureTangent: Sendable, Equatable {
    public let direction: SIMD3<Float>
    public let handedness: Float
    public let hasMapping: Bool
}

/// Expanded geometry preserves UV/tangent/material seams until textured indexing
/// is implemented. No native owner, borrowed buffer or caller pixel view escapes.
public struct MeshWithBakedTextures: Sendable {
    public let geometry: Mesh
    public let metadata: MeshUvMetadata
    public let tangents: [MeshTextureTangent]
    public let textures: MeshTextureMaps
}

/// Caller-decoded straight-alpha RGBA8 input. No image framework or color conversion
/// is invoked by the SDK. Storage must represent the declared readable rows.
public struct MeshBakeImage: Sendable {
    public let imageID: String
    public let width: Int
    public let height: Int
    public let rowStride: Int
    public let pixels: Data

    /// Store image metadata; the loader validates identity, dimensions and span.
    /// - Parameters:
    ///   - imageID: Original opaque engine identity; brace aliases must be unique.
    ///   - width: Pixel width in 1...8192.
    ///   - height: Pixel height in 1...8192.
    ///   - rowStride: Bytes per row, including padding.
    ///   - pixels: Borrowed during loading, never retained by native output.
    public init(imageID: String, width: Int, height: Int, rowStride: Int, pixels: Data) {
        self.imageID = imageID
        self.width = width
        self.height = height
        self.rowStride = rowStride
        self.pixels = pixels
    }
}

/// Requested bake limits. Quotas exclude Swift copies, input storage and native
/// workspace. Native generation observes cooperative phase boundaries.
public struct MeshBakeOptions: Sendable {
    public let colorSize: Int
    public let normalSize: Int
    public let materialSize: Int
    public let atlasTextureSize: Int
    public let maximumMetadataPayloadBytes: Int
    public let maximumBakePayloadBytes: Int
    public let maximumSpatialGridEntries: Int

    /// Store requested settings; loading validates all values before conversion.
    /// - Parameters:
    ///   - colorSize: Square color map dimension in 1...8192.
    ///   - normalSize: Square normal map dimension in 1...8192.
    ///   - materialSize: Square scalar/emission map dimension in 1...8192.
    ///   - atlasTextureSize: UV packing density in 1...8192, independent of map size.
    ///   - maximumMetadataPayloadBytes: UV logical quota; zero uses 64 MiB, maximum 256 MiB.
    ///   - maximumBakePayloadBytes: Map/tangent logical quota; zero uses 256 MiB, maximum 256 MiB.
    ///   - maximumSpatialGridEntries: Fold-grid insertion quota; zero uses one million, maximum sixteen million.
    public init(
        colorSize: Int = 4096, normalSize: Int = 2048, materialSize: Int = 1024,
        atlasTextureSize: Int = 4096, maximumMetadataPayloadBytes: Int = 0,
        maximumBakePayloadBytes: Int = 0, maximumSpatialGridEntries: Int = 0
    ) {
        self.colorSize = colorSize
        self.normalSize = normalSize
        self.materialSize = materialSize
        self.atlasTextureSize = atlasTextureSize
        self.maximumMetadataPayloadBytes = maximumMetadataPayloadBytes
        self.maximumBakePayloadBytes = maximumBakePayloadBytes
        self.maximumSpatialGridEntries = maximumSpatialGridEntries
    }
}
