import Dust3DDocument
import Dust3DKit
import Foundation

/// Matching ordinary geometry and optional material output from one unchanged source snapshot.
public struct FilePreviewDocument: Sendable {
    public let mesh: IndexedMesh?
    /// One matching baked, imported or mixed source-baked representation; nil retains ordinary geometry.
    public let materials: MeshMaterialContent?
    /// Procedural baked output when that representation was prepared successfully.
    public var bakedMesh: MeshWithBakedTextures? {
        guard case .baked(let value) = materials else { return nil }
        return value
    }
    /// Authored imported material inputs when supported embedded models contribute geometry.
    public var importedMaterials: ImportedMaterialRenderData? {
        guard case .imported(let value) = materials else { return nil }
        return value
    }
    /// Owned source-aware maps and policies for mixed imported/procedural geometry.
    public var sourceBakedMesh: SourceBakedMesh? {
        guard case .sourceBaked(let value) = materials else { return nil }
        return value
    }
    /// Optional material failure; ordinary geometry remains available and the original cause survives.
    public let materialError: (any Error)?
    /// Metadata interpreted from the exact source snapshot, separately from optional material rendering.
    public let materialSourceCapabilities: MaterialSourceCapabilities

    init(
        mesh: IndexedMesh?, bakedMesh: MeshWithBakedTextures?, materialError: (any Error)?,
        materialSourceCapabilities: MaterialSourceCapabilities = .unknown
    ) {
        self.init(
            mesh: mesh, materials: bakedMesh.map(MeshMaterialContent.baked), materialError: materialError,
            materialSourceCapabilities: materialSourceCapabilities)
    }

    init(
        mesh: IndexedMesh?, materials: MeshMaterialContent?, materialError: (any Error)?,
        materialSourceCapabilities: MaterialSourceCapabilities = .unknown
    ) {
        self.mesh = mesh
        self.materials = materials
        self.materialError = materialError
        self.materialSourceCapabilities = materialSourceCapabilities
    }

    /// Select the compatibility notice for the representation actually available in the system host.
    /// - Parameters:
    ///   - materialsRendered: True only after the current GPU renderer completes a material frame.
    ///   - materialRenderingFailed: True after a GPU/material upload failure forces ordinary geometry.
    /// - Returns: Remaining source/representation limitations, retaining unknown warnings verbatim.
    public func compatibilityWarning(materialsRendered: Bool = false, materialRenderingFailed: Bool = false) -> String?
    {
        MaterialPreviewWarning.message(
            mesh?.warning ?? "",
            hasBakedMaterials: materialsRendered && (bakedMesh != nil || sourceBakedMesh != nil)
                && !materialRenderingFailed,
            hasImportedMaterials: materialsRendered && (importedMaterials != nil || sourceBakedMesh != nil)
                && !materialRenderingFailed,
            hasSourceBakedMaterials: materialsRendered && sourceBakedMesh != nil && !materialRenderingFailed,
            hasLegacySurfaceDetails: materialSourceCapabilities.hasLegacySurfaceDetails)
    }
}

/// Serialized, bounded archive loading for read-only Finder and Quick Look workers.
public actor FilePreviewDocumentService {
    private let files = MeshFileService()
    private let materialPreparation: any ArchiveMaterialPreparing
    private var tail: Task<Void, Never>?

    /// Create a preview worker with a substitutable material boundary.
    /// - Parameters:
    ///   - materialBaker: Shared retained-asset decoder and Qt-free native baker.
    ///   - importedMaterialLoader: Bounded owned source/material preparation for embedded models.
    ///   - sourceMaterialBaker: Shared mixed imported/procedural preparation and source-aware baking.
    public init(
        materialBaker: any ArchiveTextureBaking = ArchiveTextureBakingService(),
        importedMaterialLoader: any ArchiveImportedMaterialLoading = ArchiveImportedMaterialService(),
        sourceMaterialBaker: any ArchiveSourceTextureBaking = ArchiveSourceTextureBakingService()
    ) {
        materialPreparation = ArchiveMaterialPreparationService(
            importedLoader: importedMaterialLoader, proceduralBaker: materialBaker, sourceBaker: sourceMaterialBaker)
    }

    /// Prepare a document without modifying bytes, writing caches or using editor state.
    /// - Parameter url: Local or system-granted file URL.
    /// - Returns: Ordinary geometry with optional baked/imported/source-baked materials, or an explicit empty result.
    ///   Material failures retain their original cause alongside ordinary geometry.
    /// - Throws: Original filesystem/native errors or `CancellationError` at cooperative boundaries.
    /// - Note: Archive input is at most 64 MiB; logical output/workspace are separate quotas.
    public func load(url: URL) async throws -> FilePreviewDocument {
        try Task.checkCancellation()
        let previous = tail
        let operation = Task { [self] in
            await previous?.value
            try Task.checkCancellation()
            return try await loadNow(url: url)
        }
        tail = Task { _ = await operation.result }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    private static let materialOptions: ArchiveMaterialPreparationOptions = {
        let mib = 1024 * 1024
        let images = ArchiveTextureLimits(
            maximumEncodedImageBytes: 16 * mib, maximumEncodedTotalBytes: 32 * mib, maximumDecodedTotalBytes: 64 * mib)
        let materialFacts = ImportedMaterialOptions(
            maximumNativePayloadBytes: 64 * mib, maximumCopiedPayloadBytes: 64 * mib)
        return ArchiveMaterialPreparationOptions(
            imported: ImportedMaterialRenderLimits(
                surface: ImportedSurfaceOptions(
                    maximumNativePayloadBytes: 64 * mib, maximumCopiedPayloadBytes: 64 * mib),
                materials: materialFacts),
            procedural: MeshBakeOptions(
                colorSize: 512, normalSize: 256, materialSize: 128, atlasTextureSize: 512,
                maximumMetadataPayloadBytes: 16 * mib, maximumBakePayloadBytes: 32 * mib),
            proceduralLimits: images,
            source: SourceMeshBakeOptions(
                bake: MeshBakeOptions(
                    colorSize: 512, normalSize: 256, materialSize: 256, atlasTextureSize: 256,
                    maximumMetadataPayloadBytes: 16 * mib, maximumBakePayloadBytes: 32 * mib),
                maximumSamplerPayloadBytes: 32 * mib, maximumAtlasPayloadBytes: 32 * mib,
                maximumNativePayloadBytes: 64 * mib, maximumCopiedPayloadBytes: 64 * mib,
                maximumInputImageBytes: 64 * mib),
            sourceLimits: ArchiveSourceTextureLimits(materials: materialFacts, textures: images))
    }()

    private func loadNow(url: URL) async throws -> FilePreviewDocument {
        let data = try await files.readArchive(url: url, maximumBytes: 64 * 1024 * 1024)
        try Task.checkCancellation()
        let document = try Dust3DDocument(data: data)
        let contents = try document.editorContents()
        let components = try document.components()
        guard components.allSatisfy({ $0.isGroup || $0.partID != nil }) else {
            // A partial procedural mesh must not masquerade as a preview of an embedded model.
            throw FilePreviewError.unavailable(
                "Embedded or unsupported component links cannot yet be rendered in file previews.")
        }
        let capabilities = MaterialSourceCapabilities.known(
            hasLegacySurfaceDetails: components.contains { $0.hasLegacySurfaceDetails })
        let excluded = Set(contents.parts.filter { $0.isDisabled || $0.target == .cutFace }.map(\.id))
        guard contents.nodes.contains(where: { node in node.partID.map { !excluded.contains($0) } ?? true }) else {
            return FilePreviewDocument(
                mesh: nil, bakedMesh: nil, materialError: nil, materialSourceCapabilities: capabilities)
        }
        let session = try MeshGenerationSession(maximumCachePayloadBytes: 16 * 1024 * 1024)
        let ordinary = try await session.generateIndexed(data: data, maximumPayloadBytes: 64 * 1024 * 1024)
        try Task.checkCancellation()
        guard let mesh = ordinary.mesh else {
            return FilePreviewDocument(
                mesh: nil, bakedMesh: nil, materialError: nil, materialSourceCapabilities: capabilities)
        }
        do {
            let materials = try await materialPreparation.load(data: data, options: Self.materialOptions)
            try Task.checkCancellation()
            return FilePreviewDocument(
                mesh: mesh, materials: materials, materialError: nil, materialSourceCapabilities: capabilities)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return FilePreviewDocument(
                mesh: mesh, bakedMesh: nil, materialError: error, materialSourceCapabilities: capabilities)
        }
    }
}
