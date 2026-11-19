import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation

struct ComponentColorDraftPreviewTarget: Equatable, Sendable {
    let context: CanvasAdjustmentTarget
    let componentIDs: [String]
}

protocol ComponentColorDraftPreviewServing: Sendable {
    func generate(_ data: Data, scopeID: UUID) async throws -> IndexedMesh?
}

struct OrdinaryColorDraftPreviewService: ComponentColorDraftPreviewServing {
    let preview: any EditorPreviewServing

    func generate(_ data: Data, scopeID: UUID) async throws -> IndexedMesh? {
        try await preview.generate(data, scopeID: scopeID).mesh
    }
}
