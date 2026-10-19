import Foundation

/// Model facts and decoded source pixels aligned with the surface model catalog.
public struct ImportedRenderMaterial: Sendable {
    public let id: ImportedSurfaceIdentity
    public let definition: ImportedModelMaterial
    public let image: ImportedDecodedImage?
}

/// One unchanged archive's copied geometry/source facts, materials and source pixels.
public struct ImportedMaterialRenderData: Sendable {
    public let surface: ImportedSurfaceMesh
    public let materials: [ImportedRenderMaterial]
    /// Aggregate decoded RGBA byte storage, independent of source/fact-copy quotas.
    public let decodedPayloadBytes: Int
}

/// Layered source/fact ownership and aggregate decoded-pixel limits; not an RSS cap.
public struct ImportedMaterialRenderLimits: Sendable {
    public let surface: ImportedSurfaceOptions
    public let materials: ImportedMaterialOptions
    public let maximumEncodedImageBytes: Int
    public let maximumDecodedTotalBytes: Int

    /// Configure preparation quotas without changing preserved archive assets.
    /// - Parameters:
    ///   - surface: Independent native and Swift source ownership limits.
    ///   - materials: Independent native and Swift material/fact ownership limits.
    ///   - maximumEncodedImageBytes: Per-image input limit, 1...256 MiB; default 16 MiB.
    ///   - maximumDecodedTotalBytes: Aggregate RGBA storage, 1...256 MiB; default 64 MiB.
    /// - Note: Temporary lookups, codec/generator workspace and allocator overhead are excluded.
    public init(
        surface: ImportedSurfaceOptions = .init(), materials: ImportedMaterialOptions = .init(),
        maximumEncodedImageBytes: Int = 16 * 1024 * 1024,
        maximumDecodedTotalBytes: Int = 64 * 1024 * 1024
    ) {
        self.surface = surface
        self.materials = materials
        self.maximumEncodedImageBytes = maximumEncodedImageBytes
        self.maximumDecodedTotalBytes = maximumDecodedTotalBytes
    }
}

/// Preparation failures supplement original native/codec diagnostics rather than replacing them.
public enum ImportedMaterialRenderError: LocalizedError, Equatable, Sendable {
    case invalidLimits
    case missingMaterial(String)
    case duplicateMaterial(String)
    case decodedLimitExceeded(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits: return "The imported-material rendering limits are invalid."
        case .missingMaterial(let id): return "The generated surface has no matching imported material: \(id)."
        case .duplicateMaterial(let id): return "The imported material identity is ambiguous: \(id)."
        case .decodedLimitExceeded(let id): return "Decoded imported textures exceed the aggregate limit at \(id)."
        }
    }
}
