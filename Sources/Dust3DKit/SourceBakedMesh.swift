import Foundation

/// Material policy for a final baked triangle. Color factors are already in the maps.
public struct SourceBakedPolicy: Sendable, Equatable {
    public let alphaMode: ImportedAlphaMode
    public let alphaCutoff: Double
    public let isDoubleSided: Bool
}

/// One final float-retained triangle; missing mappings and policy remain explicit.
public struct SourceBakedTriangle: Sendable, Equatable {
    public let packedUVs: MeshUvCorners?
    public let tangent: MeshTextureTangent
    public let policy: SourceBakedPolicy?
    public let modelIndex: Int?
    public let componentIndex: Int?
}

/// Independent Swift-owned geometry, records, catalogs and pixels. No native pointers escape.
public struct SourceBakedMesh: Sendable {
    public let geometry: Mesh
    public let triangles: [SourceBakedTriangle]
    public let modelIDs: [ImportedSurfaceIdentity]
    public let components: [ImportedSurfaceComponent]
    public let textures: MeshTextureMaps
    /// Owned additional/base chains by map role; empty for existing base-only native loading.
    public let mipmaps: SourceBakedMipmaps
    /// Clamp atlas sampling to this LOD. Generating global mixed-chart mipmaps is unsafe.
    public let maximumSamplingLod: Double
    public let nativePayloadBytes: Int
    /// Retained Swift logical bytes; excludes allocator overhead and temporary workspace.
    public let copiedPayloadBytes: Int

    init(
        geometry: Mesh, triangles: [SourceBakedTriangle], modelIDs: [ImportedSurfaceIdentity],
        components: [ImportedSurfaceComponent], textures: MeshTextureMaps,
        mipmaps: SourceBakedMipmaps = SourceBakedMipmaps(), maximumSamplingLod: Double,
        nativePayloadBytes: Int, copiedPayloadBytes: Int
    ) {
        self.geometry = geometry
        self.triangles = triangles
        self.modelIDs = modelIDs
        self.components = components
        self.textures = textures
        self.mipmaps = mipmaps
        self.maximumSamplingLod = maximumSamplingLod
        self.nativePayloadBytes = nativePayloadBytes
        self.copiedPayloadBytes = copiedPayloadBytes
    }
}

/// Caller-decoded, source-matched straight-alpha RGBA8 pixels for an imported model.
public struct SourceMeshBakeImage: Sendable {
    public let modelID: String
    public let width: Int
    public let height: Int
    public let rowStride: Int
    public let pixels: Data

    /// Store a decoded image; loading checks identity, dimensions, span and aggregate limits.
    /// - Parameters:
    ///   - modelID: Exact model identity, 1...128 UTF-8 bytes, without NUL.
    ///   - width: Pixel width in 1...8192.
    ///   - height: Pixel height in 1...8192.
    ///   - rowStride: Readable bytes per row, including padding.
    ///   - pixels: Source-matched RGBA8 bytes; not retained by native output.
    public init(modelID: String, width: Int, height: Int, rowStride: Int, pixels: Data) {
        self.modelID = modelID
        self.width = width
        self.height = height
        self.rowStride = rowStride
        self.pixels = pixels
    }

    /// Use pixels decoded from the same archive's imported material image.
    /// - Parameter decodedImage: Owned decoder output, without material factors applied.
    public init(decodedImage: ImportedDecodedImage) {
        self.init(
            modelID: decodedImage.modelID, width: decodedImage.width, height: decodedImage.height,
            rowStride: decodedImage.rowStride, pixels: decodedImage.pixels)
    }
}

/// Independent native, copied-output and caller-input limits. These are not process RSS limits.
public struct SourceMeshBakeOptions: Sendable {
    public let bake: MeshBakeOptions
    public let maximumSamplerPayloadBytes: Int
    public let maximumAtlasPayloadBytes: Int
    public let maximumNativePayloadBytes: Int
    public let maximumCopiedPayloadBytes: Int
    public let maximumInputImageBytes: Int
    public let maximumChartCount: Int
    public let maximumRasterSamples: Int
    public let maximumMipLevels: Int

    /// Configure source baking; all values are checked before native conversion.
    /// - Parameters:
    ///   - bake: Legacy map dimensions and procedural UV/bake workspace limits.
    ///   - maximumSamplerPayloadBytes: Zero selects 64 MiB; maximum 256 MiB.
    ///   - maximumAtlasPayloadBytes: Zero selects 64 MiB; maximum 256 MiB.
    ///   - maximumNativePayloadBytes: Zero selects 256 MiB; maximum 256 MiB.
    ///   - maximumCopiedPayloadBytes: Positive Swift output quota, at most 256 MiB.
    ///   - maximumInputImageBytes: Positive aggregate decoded storage quota, at most 256 MiB.
    ///   - maximumChartCount: Zero selects 50000; maximum 100000.
    ///   - maximumRasterSamples: Zero selects 250 million; maximum one billion.
    ///   - maximumMipLevels: Zero keeps base-only loading; 1...14 opts into isolated mip baking.
    public init(
        bake: MeshBakeOptions = MeshBakeOptions(), maximumSamplerPayloadBytes: Int = 0,
        maximumAtlasPayloadBytes: Int = 0, maximumNativePayloadBytes: Int = 0,
        maximumCopiedPayloadBytes: Int = 256 * 1024 * 1024, maximumInputImageBytes: Int = 64 * 1024 * 1024,
        maximumChartCount: Int = 0, maximumRasterSamples: Int = 0, maximumMipLevels: Int = 0
    ) {
        self.bake = bake
        self.maximumSamplerPayloadBytes = maximumSamplerPayloadBytes
        self.maximumAtlasPayloadBytes = maximumAtlasPayloadBytes
        self.maximumNativePayloadBytes = maximumNativePayloadBytes
        self.maximumCopiedPayloadBytes = maximumCopiedPayloadBytes
        self.maximumInputImageBytes = maximumInputImageBytes
        self.maximumChartCount = maximumChartCount
        self.maximumRasterSamples = maximumRasterSamples
        self.maximumMipLevels = maximumMipLevels
    }
}

/// Swift boundary failures; native generation failures preserve MeshLoadingError status and cause.
public enum SourceMeshBakeError: LocalizedError, Sendable, Equatable {
    case invalidLimits, invalidInputImage, inputLimitExceeded, invalidNativeCounts
    case copyLimitExceeded, invalidCatalog, invalidTriangle, invalidPolicy, invalidSamplingLod

    /// Describe the exact Swift ownership/input failure while preserving its typed identity.
    public var errorDescription: String? {
        switch self {
        case .invalidLimits: "The source-baking limits are invalid."
        case .invalidInputImage: "A source image has invalid identity, dimensions, row stride or pixel storage."
        case .inputLimitExceeded: "Decoded source texture inputs exceed the configured input limit."
        case .invalidNativeCounts: "The engine returned inconsistent source-baked counts."
        case .copyLimitExceeded:
            "Copied source-baked geometry, metadata or textures exceed the configured output limit."
        case .invalidCatalog: "The engine returned invalid source-baked model or component catalogs."
        case .invalidTriangle: "The engine returned invalid source-baked triangle UVs, tangents or references."
        case .invalidPolicy: "The engine returned an invalid source-baked alpha or sidedness policy."
        case .invalidSamplingLod: "The engine returned an invalid source-atlas sampling LOD."
        }
    }
}
