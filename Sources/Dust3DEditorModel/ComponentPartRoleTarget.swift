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

extension EditorSnapshot {
    /// The shared role of directly linked selected parts, with groups contributing no descendants.
    public var selectedComponentPartRole: PartTarget? {
        let ids = Set(selectedComponentRows.compactMap { $0.component.partID }.map { Data($0.utf8) })
        guard !ids.isEmpty else { return nil }
        let parts = self.parts.filter { ids.contains(Data($0.id.utf8)) }
        guard parts.count == ids.count, let first = parts.first?.target,
            parts.allSatisfy({ $0.target == first })
        else { return nil }
        return first
    }

}
