import Dust3DDocument

/// Captures the sole exact linked Model part behind explicit node and edge picks.
package struct GraphModelPartTarget: Sendable {
    private let owner: GraphPartRoleTarget
    package let part: DocumentPart?

    package init(snapshot: EditorSnapshot) {
        self.init(owner: GraphPartRoleTarget(snapshot: snapshot))
    }

    package init(owner: GraphPartRoleTarget) {
        self.owner = owner
        part = owner.part?.target == .model ? owner.part : nil
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
