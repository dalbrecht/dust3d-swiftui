import Dust3DDocument

/// A role edit targets the one exact linked part owned by the explicit graph picks.
package struct GraphPartRoleTarget: Sendable {
    private let owner: ComponentMeshSelectionTarget
    package let part: DocumentPart?

    package init(snapshot: EditorSnapshot) {
        owner = ComponentMeshSelectionTarget(graphSelection: snapshot)
        part = owner.soleGraphLinkedPart(in: snapshot)
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        part != nil && owner.isCurrent(in: snapshot)
    }
}
