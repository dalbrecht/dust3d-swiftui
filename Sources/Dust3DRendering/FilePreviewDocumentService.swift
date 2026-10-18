import Dust3DDocument
import Dust3DKit
import Foundation

/// Matching ordinary geometry and optional baked output from one unchanged source snapshot.
public struct FilePreviewDocument: Sendable {
    public let mesh: IndexedMesh?
    public let bakedMesh: MeshWithBakedTextures?
    /// Optional material failure; ordinary geometry remains available and the original cause survives.
    public let materialError: (any Error)?
}

/// Serialized, bounded archive loading for read-only Finder and Quick Look workers.
public actor FilePreviewDocumentService {
    private let files = MeshFileService()
    private let materialBaker: any ArchiveTextureBaking
    private var tail: Task<Void, Never>?

    /// Create a preview worker with a substitutable material boundary.
    /// - Parameter materialBaker: Shared retained-asset decoder and Qt-free native baker.
    public init(materialBaker: any ArchiveTextureBaking = ArchiveTextureBakingService()) {
        self.materialBaker = materialBaker
    }

    /// Prepare a document without modifying bytes, writing caches or using editor state.
    /// - Parameter url: Local or system-granted file URL.
    /// - Returns: Ordinary/baked geometry, or an explicit empty result; material failures retain their cause.
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
        let excluded = Set(contents.parts.filter { $0.isDisabled || $0.target == .cutFace }.map(\.id))
        guard contents.nodes.contains(where: { node in node.partID.map { !excluded.contains($0) } ?? true }) else {
            return FilePreviewDocument(mesh: nil, bakedMesh: nil, materialError: nil)
        }
        let session = try MeshGenerationSession(maximumCachePayloadBytes: 16 * 1024 * 1024)
        let ordinary = try await session.generateIndexed(data: data, maximumPayloadBytes: 64 * 1024 * 1024)
        try Task.checkCancellation()
        guard let mesh = ordinary.mesh else {
            return FilePreviewDocument(mesh: nil, bakedMesh: nil, materialError: nil)
        }
        do {
            let baked = try await materialBaker.load(
                data: data,
                options: MeshBakeOptions(
                    colorSize: 512, normalSize: 256, materialSize: 128, atlasTextureSize: 512,
                    maximumMetadataPayloadBytes: 16 * 1024 * 1024, maximumBakePayloadBytes: 32 * 1024 * 1024),
                limits: ArchiveTextureLimits(
                    maximumEncodedImageBytes: 16 * 1024 * 1024, maximumEncodedTotalBytes: 32 * 1024 * 1024,
                    maximumDecodedTotalBytes: 64 * 1024 * 1024))
            try Task.checkCancellation()
            return FilePreviewDocument(mesh: mesh, bakedMesh: baked, materialError: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return FilePreviewDocument(mesh: mesh, bakedMesh: nil, materialError: error)
        }
    }
}
