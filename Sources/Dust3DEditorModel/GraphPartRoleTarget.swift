import Dust3DDocument

/// Captures the sole exact linked part behind explicit graph picks, regardless of its role.
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
