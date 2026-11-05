import Dust3DDocument
import Foundation

/// A queued role action must retain its original document, component selection and constraint epochs.
public struct ComponentPartRoleTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    public init(snapshot: EditorSnapshot) { context = CanvasAdjustmentTarget(snapshot: snapshot) }
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { context.isCurrent(in: snapshot) }
}

public enum ComponentPartRoleError: Error, Equatable, Sendable {
    case staleContext
}

extension EditorSnapshot {
    /// Selected groups contribute no descendants; unsupported owner/hierarchy combinations remain unavailable.
    public func componentPartRolePlan(_ target: PartTarget) throws -> ComponentPartRolePlan {
        try ComponentPartRolePlan(
            components: componentTree.rows.map(\.component), parts: parts,
            componentIDs: selectedComponentIDs.sorted(), target: target)
    }
}
