import Foundation

/// Explicit root/group destinations avoid using a missing selection as an implicit root move.
public enum ComponentParent: Hashable, Sendable {
    case root
    case component(String)

    /// Document command parent identity; nil explicitly denotes the root container.
    public var componentID: String? {
        switch self {
        case .root: return nil
        case .component(let id): return id
        }
    }
}

/// A supported destination presented in unchanged document order.
public struct ComponentParentOption: Identifiable, Equatable, Sendable {
    public let id: ComponentParent
    public let title: String
}

/// Captured window/document/selection identity for a transient parent-selection draft.
public struct ComponentReparentTarget: Sendable {
    public let componentID: String
    private let documentIdentity: UUID
    private let documentRevision: Int

    /// Capture a singleton component selection; ambiguous or empty selections produce no target.
    /// - Parameter snapshot: Current immutable editing snapshot.
    public init?(snapshot: EditorSnapshot) {
        guard let id = snapshot.selectedComponentID else { return nil }
        componentID = id
        documentIdentity = snapshot.documentIdentity
        documentRevision = snapshot.documentRevision
    }

    /// Check the captured document epoch and singleton identity before any mutation.
    /// - Parameter snapshot: Current snapshot from the same editing session.
    /// - Returns: False after document replacement, any committed edit (including Undo), or a different selection.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && documentRevision == snapshot.documentRevision
            && componentID == snapshot.selectedComponentID
    }
}
