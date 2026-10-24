import Foundation

/// Identity of a captured export, independent of window selection and interaction locks.
/// This metadata does not enable native encoding or hold a publication lease.
public struct EditorExportTarget: Sendable {
    let documentIdentity: UUID
    let documentRevision: Int

    /// Capture an accepted snapshot before starting background export work.
    /// - Parameter snapshot: Current document identity and monotonic semantic revision.
    /// - Example: `let target = EditorExportTarget(snapshot: snapshot)`.
    public init(snapshot: EditorSnapshot) {
        documentIdentity = snapshot.documentIdentity
        documentRevision = snapshot.documentRevision
    }
}
