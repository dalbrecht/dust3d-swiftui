import Dust3DDocument

/// Captures the sole exact linked Model part behind explicit node and edge picks.
package struct GraphModelPartTarget: Sendable {
    private let owner: ComponentMeshSelectionTarget
    package let part: DocumentPart?

    package init(snapshot: EditorSnapshot) {
        owner = ComponentMeshSelectionTarget(graphSelection: snapshot)
        guard owner.ids.count == 1, let componentID = owner.ids.first,
            let partID = snapshot.componentTree.rows.first(where: { $0.id.utf8.elementsEqual(componentID.utf8) })?
                .component.partID
        else {
            part = nil
            return
        }
        part = snapshot.parts.first { $0.target == .model && $0.id.utf8.elementsEqual(partID.utf8) }
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        part != nil && owner.isCurrent(in: snapshot)
    }
}

package typealias GraphPartCrossSectionTarget = GraphModelPartTarget

package enum GraphPartCrossSectionEdit: Sendable {
    case profile(CutFaceSelection)
    case rotation(Double)
    case deformationScale(PartDeformationProperty, Double)
    case deformationUnified(Bool)
}
