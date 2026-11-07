import Dust3DDocument

/// Captures the sole exact linked Model part behind explicit node and edge picks.
package struct GraphPartCrossSectionTarget: Sendable {
    private let owner: ComponentMeshSelectionTarget
    package let part: DocumentPart?

    package init(snapshot: EditorSnapshot) {
        owner = ComponentMeshSelectionTarget(graphSelection: snapshot)
        let linkedPart = owner.soleGraphLinkedPart(in: snapshot)
        part = linkedPart?.target == .model ? linkedPart : nil
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        part != nil && owner.isCurrent(in: snapshot)
    }
}

package enum GraphPartCrossSectionEdit: Sendable {
    case profile(CutFaceSelection)
    case rotation(Double)
    case deformationScale(PartDeformationProperty, Double)
    case deformationUnified(Bool)
}
