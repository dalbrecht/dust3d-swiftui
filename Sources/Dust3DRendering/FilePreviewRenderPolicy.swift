import CoreGraphics
import Dust3DKit
import Foundation

/// Owned thumbnail pixels with the original optional-material cause retained after fallback.
public struct FilePreviewRenderedImage: Sendable {
    public let image: FilePreviewImage
    /// Preparation/rendering failure when ordinary geometry was used; nil for successful materials.
    public let materialError: (any Error)?
}

/// Preserve both failures when optional material rendering and ordinary fallback fail.
public enum FilePreviewRenderingError: LocalizedError, Sendable {
    case geometryFallbackFailed(materialCause: any Error, geometryCause: any Error)

    public var errorDescription: String? {
        switch self {
        case .geometryFallbackFailed(let material, let geometry):
            return
                "Material preview failed: \(material.localizedDescription) Geometry fallback failed: \(geometry.localizedDescription)"
        }
    }
}

extension FilePreviewRenderer {
    /// Render the prepared representation, falling back to ordinary geometry after an optional-material failure.
    /// - Parameters:
    ///   - document: Immutable geometry/materials from one read-only archive snapshot.
    ///   - maximumSize: Requested point bounds, limited to 2048 pixels per output side.
    ///   - scale: Positive display scale, at most eight.
    /// - Returns: Owned image and original material cause if fallback was required.
    /// - Throws: Original geometry/request error, paired FilePreviewRenderingError, or CancellationError.
    /// - Note: Cancellation never starts fallback work. Valid transparent materials remain transparent.
    /// - Example: `let result = try await FilePreviewRenderer.render(document: preview, maximumSize: size, scale: 1)`.
    @MainActor
    public static func render(
        document: FilePreviewDocument, maximumSize: CGSize, scale: CGFloat
    ) async throws -> FilePreviewRenderedImage {
        try Task.checkCancellation()
        _ = try FilePreviewDimensions(maximumSize: maximumSize, scale: scale)
        return try await FilePreviewRenderPolicy.render(
            document: document,
            renderMaterials: { materials in
                switch materials {
                case .baked(let value):
                    try await render(bakedMesh: value, maximumSize: maximumSize, scale: scale)
                case .sourceBaked(let value):
                    try await render(sourceBakedMesh: value, maximumSize: maximumSize, scale: scale)
                case .imported(let value):
                    try await render(importedMaterials: value, maximumSize: maximumSize, scale: scale)
                }
            },
            renderGeometry: { mesh in try await render(mesh: mesh, maximumSize: maximumSize, scale: scale) })
    }
}

/// CPU-testable fallback orchestration, with no device or window dependency.
@MainActor
enum FilePreviewRenderPolicy {
    static func render(
        document: FilePreviewDocument,
        renderMaterials: @MainActor (MeshMaterialContent) async throws -> FilePreviewImage,
        renderGeometry: @MainActor (IndexedMesh) async throws -> FilePreviewImage
    ) async throws -> FilePreviewRenderedImage {
        try Task.checkCancellation()
        guard let mesh = document.mesh else {
            throw FilePreviewError.unavailable("This document has no visible mesh to thumbnail.")
        }
        if let materials = document.materials {
            do {
                let image = try await renderMaterials(materials)
                try Task.checkCancellation()
                return FilePreviewRenderedImage(image: image, materialError: document.materialError)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let materialCause = error
                try Task.checkCancellation()
                do {
                    let image = try await renderGeometry(mesh)
                    try Task.checkCancellation()
                    return FilePreviewRenderedImage(image: image, materialError: materialCause)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    throw FilePreviewRenderingError.geometryFallbackFailed(
                        materialCause: materialCause, geometryCause: error)
                }
            }
        }
        let image = try await renderGeometry(mesh)
        try Task.checkCancellation()
        return FilePreviewRenderedImage(image: image, materialError: document.materialError)
    }
}
