import Dust3DDocument

/// The Shift-drag action is selected once, from the captured graph and pointer anchor.
public struct CanvasShiftDrag: Sendable {
    private let snapshot: EditorSnapshot
    private let target: CanvasAdjustmentTarget
    private let effective: [DocumentNode]
    private let endpoint: EndpointIKTarget?
    public let projection: CanvasProjection

    public init(anchorID: String, snapshot: EditorSnapshot, projection: CanvasProjection) throws {
        guard let anchor = snapshot.nodes.first(where: { $0.id == anchorID }), anchor.isEditable else {
            throw EditorError.readOnlyNode
        }
        self.snapshot = snapshot
        self.projection = projection
        target = CanvasAdjustmentTarget(snapshot: snapshot)
        effective = snapshot.transformNodeIDs.contains(anchorID) ? snapshot.transformNodes : [anchor]
        endpoint =
            effective.count == 1
            ? EndpointIKTarget(endpointID: anchorID, snapshot: snapshot)
            : nil
    }

    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { target.isCurrent(in: snapshot) }

    public func updates(by translation: CanvasPoint) throws -> [NodeUpdate] {
        guard translation.x.isFinite, translation.y.isFinite else { throw DocumentError.invalidNode }
        if let endpoint {
            return try endpoint.updates(toward: projection.moving(endpoint.endpointPosition, by: translation))
        }
        return try CanvasRotation.updates(
            degrees: translation.x.rounded(.towardZero), plane: projection.plane, snapshot: snapshot,
            effective: effective)
    }
}
