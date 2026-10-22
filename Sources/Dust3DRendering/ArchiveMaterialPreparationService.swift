import Dust3DKit
import Foundation

/// Independent resource policies for the selected archive-material representation.
public struct ArchiveMaterialPreparationOptions: Sendable {
    public let selectionSurface: ImportedSurfaceOptions
    public let imported: ImportedMaterialRenderLimits
    public let procedural: MeshBakeOptions
    public let proceduralLimits: ArchiveTextureLimits
    public let source: SourceMeshBakeOptions
    public let sourceLimits: ArchiveSourceTextureLimits

    /// Configure selected-path limits; codec/generator workspace is not a process-memory cap.
    /// - Parameters:
    ///   - selectionSurface: Independent temporary geometry inspection, with no pixel decoding.
    ///   - imported: Inspection and decoded inputs for authored source rendering.
    ///   - procedural: Legacy bake dimensions and output quotas for procedural-only geometry.
    ///   - proceduralLimits: Retained image limits for that legacy bake.
    ///   - source: Mixed-surface bake quotas; default atlas fits every default output map.
    ///   - sourceLimits: Combined imported/procedural image admission for mixed surfaces.
    public init(
        selectionSurface: ImportedSurfaceOptions = .init(),
        imported: ImportedMaterialRenderLimits = .init(),
        procedural: MeshBakeOptions = MeshBakeOptions(
            colorSize: 512, normalSize: 256, materialSize: 128, atlasTextureSize: 512),
        proceduralLimits: ArchiveTextureLimits = .init(),
        source: SourceMeshBakeOptions = SourceMeshBakeOptions(
            bake: MeshBakeOptions(colorSize: 512, normalSize: 256, materialSize: 256, atlasTextureSize: 256)),
        sourceLimits: ArchiveSourceTextureLimits = .init()
    ) {
        self.selectionSurface = selectionSurface
        self.imported = imported
        self.procedural = procedural
        self.proceduralLimits = proceduralLimits
        self.source = source
        self.sourceLimits = sourceLimits
    }
}

/// One immutable archive snapshot to one coherent optional-material representation.
public protocol ArchiveMaterialPreparing: Sendable {
    /// Prepare materials independently of observable state and GPU resources.
    /// - Parameters: data is complete archive bytes; options bound selected-path ownership layers.
    /// - Returns: Authored imported, procedural baked, or mixed source-baked material content.
    /// - Throws: Original source, codec, quota, native or cancellation error.
    func load(data: Data, options: ArchiveMaterialPreparationOptions) async throws -> MeshMaterialContent
}

/// Shared background representation selection for native apps and file previews.
public actor ArchiveMaterialPreparationService: ArchiveMaterialPreparing {
    private let importedLoader: any ArchiveImportedMaterialLoading
    private let proceduralBaker: any ArchiveTextureBaking
    private let sourceBaker: any ArchiveSourceTextureBaking

    /// Create substitutable preparation boundaries without retaining document or GPU state.
    /// - Parameters: importedLoader inspects source geometry; proceduralBaker and sourceBaker own their bake paths.
    public init(
        importedLoader: any ArchiveImportedMaterialLoading = ArchiveImportedMaterialService(),
        proceduralBaker: any ArchiveTextureBaking = ArchiveTextureBakingService(),
        sourceBaker: any ArchiveSourceTextureBaking = ArchiveSourceTextureBakingService()
    ) {
        self.importedLoader = importedLoader
        self.proceduralBaker = proceduralBaker
        self.sourceBaker = sourceBaker
    }

    /// Select supported materials from the exact bytes, preserving original failures and cancellation.
    /// - Parameters: data is unchanged source bytes; options are separate quotas for each representation.
    /// - Returns: One immutable material input matching this archive snapshot.
    /// - Throws: Original preparation error or cancellation before/after an asynchronous boundary.
    /// - Note: Geometry inspection is released before selected-path image preparation begins.
    /// - Example: `let materials = try await ArchiveMaterialPreparationService().load(data: archive)`.
    public func load(data: Data, options: ArchiveMaterialPreparationOptions = .init()) async throws
        -> MeshMaterialContent
    {
        try Task.checkCancellation()
        let choice = try await importedLoader.selectForPreparation(
            data: data, limits: options.imported, inspectionLimits: options.selectionSurface)
        try Task.checkCancellation()
        let result: MeshMaterialContent
        switch choice {
        case .imported(let imported): result = .imported(imported)
        case .procedural:
            result = .baked(
                try await proceduralBaker.load(
                    data: data, options: options.procedural, limits: options.proceduralLimits))
        case .mixed:
            result = .sourceBaked(
                try await sourceBaker.load(data: data, options: options.source, limits: options.sourceLimits))
        }
        try Task.checkCancellation()
        return result
    }

}
