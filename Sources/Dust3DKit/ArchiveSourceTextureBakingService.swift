import Foundation

/// Independent imported-inspection quotas and combined imported/procedural encoded/decoded image limits.
public struct ArchiveSourceTextureLimits: Sendable {
    public let materials: ImportedMaterialOptions
    public let textures: ArchiveTextureLimits

    /// Configure retained-input admission. Native workspace and archive storage are separate.
    /// - Parameters:
    ///   - materials: Native/Swift copied imported material and encoded-image inspection quotas.
    ///   - textures: Combined image admission; decoded storage is also capped by source bake options.
    public init(
        materials: ImportedMaterialOptions = .init(),
        textures: ArchiveTextureLimits = ArchiveTextureLimits(maximumDecodedTotalBytes: 64 * 1024 * 1024)
    ) {
        self.materials = materials
        self.textures = textures
    }
}

/// Preserve the exact model key and original codec failure for optional bake diagnostics.
public enum ArchiveSourceTextureBakingError: LocalizedError, Sendable {
    case importedImageDecoding(modelID: String, cause: any Error)

    /// Describe the failed model while retaining its underlying typed cause.
    public var errorDescription: String? {
        switch self {
        case .importedImageDecoding(let modelID, let cause):
            return "Could not decode imported model image \(modelID): \(cause.localizedDescription)"
        }
    }
}

/// Archive-to-source-bake boundary suitable for revision-guarded preview/export consumers.
public protocol ArchiveSourceTextureBaking: Sendable {
    /// Prepare one unchanged archive snapshot and bake its imported/procedural surfaces.
    /// - Parameters: data is complete archive bytes; options and limits bound independent ownership layers.
    /// - Returns: Owned source-aware geometry, policy, UVs, pixels and atlas LOD restriction.
    /// - Throws: Original document/native error, per-image codec cause, quota error or cancellation.
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
}

/// Background preparation; decoding and baking never mutate the input document.
public actor ArchiveSourceTextureBakingService: ArchiveSourceTextureBaking {
    private let baker: any ArchiveSourceBakingOperation

    /// Create a source-aware baker without retaining a native mesh or archive cache.
    public init() { baker = NativeArchiveSourceBakingOperation() }
    init(baker: any ArchiveSourceBakingOperation) { self.baker = baker }

    /// Resolve both supported material paths from one immutable snapshot off the main actor.
    /// - Parameters:
    ///   - data: Complete lossless `.ds3` archive, never re-encoded by this operation.
    ///   - options: Source-bake dimensions, native quotas and Swift input/output limits.
    ///   - limits: Imported inspection and combined image admission budgets.
    /// - Returns: Independent Swift source-baked output. Respect its maximumSamplingLod.
    /// - Throws: Original native/document errors, ArchiveTextureBakingError, contextual imported codec errors,
    ///   SourceMeshBakeError, ImportedMaterialError or CancellationError.
    /// - Note: All declared required imported textures are decoded. Limits exclude codec/generator workspace.
    /// - Example: `let result = try await ArchiveSourceTextureBakingService().load(data: archive)`.
    public func load(data: Data, options: SourceMeshBakeOptions = .init(), limits: ArchiveSourceTextureLimits = .init())
        async throws -> SourceBakedMesh
    {
        try Task.checkCancellation()
        let prepared = try ArchiveSourceImagePreparation.load(data: data, options: options, limits: limits)
        try Task.checkCancellation()
        let result = try await baker.load(
            data: data, modelImages: prepared.models, images: prepared.legacy, options: options)
        try Task.checkCancellation()
        return result
    }
}

protocol ArchiveSourceBakingOperation: Sendable {
    func load(data: Data, modelImages: [SourceMeshBakeImage], images: [MeshBakeImage], options: SourceMeshBakeOptions)
        async throws -> SourceBakedMesh
}

struct NativeArchiveSourceBakingOperation: ArchiveSourceBakingOperation {
    private let service = SourceMeshBakingService()

    func load(data: Data, modelImages: [SourceMeshBakeImage], images: [MeshBakeImage], options: SourceMeshBakeOptions)
        async throws -> SourceBakedMesh
    {
        try await service.load(data: data, modelImages: modelImages, images: images, options: options)
    }
}
