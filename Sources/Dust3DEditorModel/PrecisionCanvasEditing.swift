import Dust3DDocument
import Foundation

extension EditorState {
    /// Move a supported stored origin by a captured document-space delta, retaining graph selection.
    /// - Parameters: `delta` is already converted from logical canvas units; `target` rejects stale input epochs.
    /// - Throws: Stale, unavailable origin, cancellation or bounded geometry errors atomically. Axis locks apply.
    public mutating func nudgeOrigin(by delta: NodePosition, target: CanvasAdjustmentTarget? = nil) throws {
        if let target, !target.isCurrent(in: snapshot) { throw EditorError.staleCanvasAdjustment }
        guard let origin = snapshot.origin else { throw EditorError.unavailableOrigin }
        try commitPrecisionUpdates([
            .setOrigin(.init(x: origin.x + delta.x, y: origin.y + delta.y, z: origin.z + delta.z))
        ])
    }

    /// Scale only editable merged-selection positions about their centroid, retaining every radius.
    /// - Parameters: `factor` may be zero or negative, matching Qt's signed 1±10/H spacing input;
    ///   `target` captures document, selection and constraints before queueing.
    /// - Throws: Stale, nonfinite factor, cancellation or output geometry errors without a partial edit.
    public mutating func scaleSelectionPositions(factor: Double, target: CanvasAdjustmentTarget? = nil) throws {
        if let target, !target.isCurrent(in: snapshot) { throw EditorError.staleCanvasAdjustment }
        guard factor.isFinite else { throw EditorError.invalidSpacingFactor }
        guard factor != 1 else { return }
        let current = snapshot
        let locks = current.locks
        let nodes = current.transformNodes.filter(\.isEditable)
        guard !nodes.isEmpty else { return }
        let count = Double(nodes.count)
        let center = NodePosition(
            x: nodes.reduce(0) { $0 + $1.value.position.x } / count,
            y: nodes.reduce(0) { $0 + $1.value.position.y } / count,
            z: nodes.reduce(0) { $0 + $1.value.position.z } / count)
        let updates = nodes.map { node in
            let original = node.value.position
            return NodeUpdate(
                id: node.id,
                value: .init(
                    position: .init(
                        x: locks.contains(.x) ? original.x : center.x + (original.x - center.x) * factor,
                        y: locks.contains(.y) ? original.y : center.y + (original.y - center.y) * factor,
                        z: locks.contains(.z) ? original.z : center.z + (original.z - center.z) * factor),
                    radius: node.value.radius))
        }
        try commitPrecisionUpdates([.setNodes(updates)])
    }

    private mutating func commitPrecisionUpdates(_ commands: [DocumentCommand]) throws {
        try Task.checkCancellation()
        var next = self
        try next.apply(commands)
        try Task.checkCancellation()
        self = next
    }
}
