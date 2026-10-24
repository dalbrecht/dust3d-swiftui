import Dust3DDocument
import Foundation

/// Captured row/document identity for a metadata dialog; selection and interaction locks are independent.
public struct AnimationEditTarget: Sendable {
    public let animationID: String
    private let documentIdentity: UUID
    private let documentRevision: Int

    /// Capture an existing exact row identity from one accepted actor observation.
    /// - Parameters: snapshot is the source-correlated list; animationID is an exact UTF-8 row identity.
    /// - Throws: Original catalog cause or `missingAnimation`; no archive is retained or modified.
    /// - Example: `try AnimationEditTarget(snapshot: value, animationID: row.source.id)`.
    public init(snapshot: EditorAnimationSnapshot, animationID: String) throws {
        if let cause = snapshot.list.issue { throw cause }
        let identity = Array(animationID.utf8)
        guard snapshot.list.rows.contains(where: { $0.id == identity }) else {
            throw DocumentAnimationError.missingAnimation(animationID)
        }
        self.animationID = animationID
        documentIdentity = snapshot.editor.documentIdentity
        documentRevision = snapshot.editor.documentRevision
    }

    /// Compare source epochs only; the actor rechecks this before applying the owned row command.
    /// - Parameter snapshot: Current accepted editor state, not an attempted replacement load.
    /// - Returns: False after semantic edits, Undo/Redo or a successful replacement Open.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && documentRevision == snapshot.documentRevision
    }
}

/// One targeted stored-intent edit, without native evaluation or timing interpretation.
public enum AnimationEdit: Sendable {
    /// Set a bounded stored display name. Example: `.rename("Rest")`.
    case rename(String)
    /// Set a bounded nonempty stored type, preserving parameters. Example: `.setType("walk")`.
    case setType(String)
    /// Set/remove a bounded unqualified parameter. Example: `.setParameter(name: "duration", value: "1.0")`.
    case setParameter(name: String, value: String?)
    /// Remove the captured row without removing its opaque assets.
    case delete

    func command(id: String) -> DocumentCommand {
        switch self {
        case .rename(let name): return .setAnimationName(id: id, name: name)
        case .setType(let type): return .setAnimationType(id: id, type: type)
        case .setParameter(let name, let value): return .setAnimationParameter(id: id, name: name, value: value)
        case .delete: return .deleteAnimation(id: id)
        }
    }
}
