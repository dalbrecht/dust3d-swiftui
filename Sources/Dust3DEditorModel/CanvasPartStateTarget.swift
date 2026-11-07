import Dust3DDocument
import Foundation

/// Captures the exact hovered graph owner or a sole explicit graph owner.
package struct CanvasPartStateTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    package let part: DocumentPart

    package init?(snapshot: EditorSnapshot, hovered: PartGraphTarget?) {
        let owner: Data?
        switch hovered {
        case .node(let id):
            owner = snapshot.nodes.first { $0.isVisible && $0.id.utf8.elementsEqual(id.utf8) }?.partID.map {
                Data($0.utf8)
            }
        case .edge(let id):
            owner = snapshot.edges.first { $0.id.utf8.elementsEqual(id.utf8) }?.partID.map { Data($0.utf8) }
        case .part:
            return nil
        case nil:
            guard let owners = snapshot.explicitGraphPartKeys(), owners.count == 1 else { return nil }
            owner = owners.first
        }
        guard let owner, let part = snapshot.parts.first(where: { Data($0.id.utf8) == owner }) else { return nil }
        self.part = part
        context = CanvasAdjustmentTarget(snapshot: snapshot)
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool { context.isCurrent(in: snapshot) }
}
