import Dust3DDocument

/// Captures the sole exact linked part behind explicit graph picks, regardless of its role.
package struct GraphPartRoleTarget: Sendable {
    private let owner: ComponentMeshSelectionTarget
    package let part: DocumentPart?
    let component: DocumentComponent?

    package init(snapshot: EditorSnapshot) {
        owner = ComponentMeshSelectionTarget(graphSelection: snapshot)
        let linked = owner.soleGraphLinkedOwner(in: snapshot)
        part = linked?.part
        component = linked?.component
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        part != nil && owner.isCurrent(in: snapshot)
    }
}
