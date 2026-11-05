import Dust3DEditorModel

/// Placement receipts keep committed graph truth independent of transient canvas cancellation.
protocol AddPlacementServing: Sendable {
    func place(_ request: AddPlacementRequest, in session: EditorSession) async throws -> AddPlacementReceipt
}
struct AddPlacementService: AddPlacementServing {
    func place(_ request: AddPlacementRequest, in session: EditorSession) async throws -> AddPlacementReceipt {
        try await session.placeAddNode(request)
    }
}
