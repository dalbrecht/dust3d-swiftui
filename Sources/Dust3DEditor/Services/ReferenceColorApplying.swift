import Dust3DEditorModel
import Foundation

/// Narrow asynchronous actor admission boundary, allowing cancellation before or after a real commit.
protocol ReferenceColorApplying: Sendable {
    func apply(
        raster: ReferenceColorRaster, layout: ReferenceColorSamplingLayout, referencePNG: Data,
        target: ReferenceColorTarget, in session: EditorSession
    ) async throws -> ReferenceColorReceipt
}
struct ReferenceColorApplicationService: ReferenceColorApplying {
    func apply(
        raster: ReferenceColorRaster, layout: ReferenceColorSamplingLayout, referencePNG: Data,
        target: ReferenceColorTarget, in session: EditorSession
    ) async throws -> ReferenceColorReceipt {
        try Task.checkCancellation()
        return try await session.autoColorSelectedParts(
            raster: raster, layout: layout,
            referencePNG: referencePNG, target: target)
    }
}
