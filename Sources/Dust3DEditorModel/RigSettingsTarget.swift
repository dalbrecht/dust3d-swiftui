import Dust3DDocument
import Foundation

/// A rendered rig control belongs to one document revision, regardless of graph selection.
package struct RigSettingsTarget: Equatable, Sendable {
    private let documentIdentity: UUID
    private let documentRevision: Int

    package init(snapshot: EditorSnapshot) {
        documentIdentity = snapshot.documentIdentity
        documentRevision = snapshot.documentRevision
    }

    func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        self == Self(snapshot: snapshot)
    }
}

package enum RigSettingsEdit: Sendable {
    case template(DocumentRigType)
    case eyelids(Bool)

    var command: DocumentCommand {
        switch self {
        case .template(let type): .setRigType(type)
        case .eyelids(let enabled): .setHeadHasEyelids(enabled)
        }
    }
}

package enum RigSettingsEditError: LocalizedError, Equatable, Sendable {
    case staleSource

    package var errorDescription: String? { "The rig settings belong to an earlier document or revision." }
}
