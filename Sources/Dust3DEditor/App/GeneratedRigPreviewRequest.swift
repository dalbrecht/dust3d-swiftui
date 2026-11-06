import Dust3DEditorModel
import Foundation

/// Actual rigs depend on assignments/settings even when ordinary mesh geometry is unchanged.
/// Captures retained immutable archive bytes; selection/palette/camera are not generation inputs.
struct GeneratedRigPreviewRequest: Sendable, Hashable {
    let documentIdentity: UUID
    let documentRevision: Int
    let archive: Data
    let sourceType: String?
    let headHasEyelids: Bool

    init(snapshot: EditorSnapshot) {
        documentIdentity = snapshot.documentIdentity
        documentRevision = snapshot.documentRevision
        archive = snapshot.document.encoded()
        sourceType = snapshot.rigSettings.sourceRigType
        headHasEyelids = snapshot.rigSettings.headHasEyelids
    }

    func matches(_ snapshot: EditorSnapshot) -> Bool { self == Self(snapshot: snapshot) }

    /// Interaction admission after full request-byte validation. Actor-owned
    /// document snapshots advance revision for edits, Undo and replacement.
    func matchesVersion(_ snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && documentRevision == snapshot.documentRevision
            && sourceType.map { Data($0.utf8) } == snapshot.rigSettings.sourceRigType.map { Data($0.utf8) }
            && headHasEyelids == snapshot.rigSettings.headHasEyelids
    }

    static func == (left: Self, right: Self) -> Bool {
        left.documentIdentity == right.documentIdentity && left.documentRevision == right.documentRevision
            && left.headHasEyelids == right.headHasEyelids
            && left.sourceType.map { Data($0.utf8) } == right.sourceType.map { Data($0.utf8) }
            && left.archive == right.archive
    }

    func hash(into hasher: inout Hasher) {
        // Cheap document/version hash; byte comparison remains part of equality.
        // Unequal archives at an identical revision may collide without coalescing.
        hasher.combine(documentIdentity)
        hasher.combine(documentRevision)
        hasher.combine(sourceType.map { Data($0.utf8) })
        hasher.combine(headHasEyelids)
    }
}
