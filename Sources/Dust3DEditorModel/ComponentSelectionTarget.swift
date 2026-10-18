import Foundation

/// Captured window/document/selection identity for a transient component operation.
public struct ComponentSelectionTarget: Sendable {
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

/// Compatibility name for existing component-parent operations.
public typealias ComponentReparentTarget = ComponentSelectionTarget

/// Captured target for asynchronous image validation and assignment.
public typealias ComponentColorImageTarget = ComponentSelectionTarget
