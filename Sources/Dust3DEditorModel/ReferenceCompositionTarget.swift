import Foundation

/// Transient document/constraint identity captured when a reference composition draft opens.
public struct ReferenceCompositionTarget: Sendable {
    let documentIdentity: UUID
    let documentRevision: Int
    let constraintRevision: Int

    /// Capture the current window's target without retaining its archive or rendered images.
    /// - Parameter snapshot: Snapshot at draft creation; selection changes do not invalidate this target.
    public init(snapshot: EditorSnapshot) {
        documentIdentity = snapshot.documentIdentity
        documentRevision = snapshot.documentRevision
        constraintRevision = snapshot.constraintRevision
    }
}
