import Dust3DDocument

/// Captures the sole exact linked Stitching Loop part behind explicit node and edge picks.
package struct GraphLoopInteriorTarget: Sendable {
    private let owner: ComponentMeshSelectionTarget
    package let part: DocumentPart?

    package init(snapshot: EditorSnapshot) {
        owner = ComponentMeshSelectionTarget(graphSelection: snapshot)
        guard owner.ids.count == 1, let id = owner.ids.first,
            let row = snapshot.componentTree.rows.first(where: { $0.id.utf8.elementsEqual(id.utf8) }),
            let partID = row.component.partID
        else {
            part = nil
            return
        }
        part = snapshot.parts.first { $0.target == .stitchingLoop && $0.id.utf8.elementsEqual(partID.utf8) }
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        part != nil && owner.isCurrent(in: snapshot)
    }
}
