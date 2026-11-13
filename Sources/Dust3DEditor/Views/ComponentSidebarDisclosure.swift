import Dust3DEditorModel
import Foundation
import Observation

/// Component disclosure belongs to the sidebar; reveal never changes graph or component selection.
@MainActor @Observable final class ComponentSidebarDisclosure {
    private(set) var epoch = UUID()
    @ObservationIgnored private var lastReveal: (document: UUID, revision: Int)?
    @ObservationIgnored private var documentIdentity: UUID?
    var collapsedIDs: Set<String> {
        didSet { if oldValue != collapsedIDs { epoch = UUID() } }
    }
    init(collapsedIDs: Set<String> = []) { self.collapsedIDs = collapsedIDs }
    func reveal(_ hint: ComponentRevealHint, documentIdentity: UUID) {
        guard lastReveal?.document != documentIdentity || lastReveal?.revision != hint.revision else { return }
        lastReveal = (documentIdentity, hint.revision)
        collapsedIDs.subtract(hint.ancestorIDs)
    }

    func restore(from snapshot: EditorSnapshot?) {
        guard documentIdentity != snapshot?.documentIdentity else { return }
        documentIdentity = snapshot?.documentIdentity
        guard let snapshot else {
            collapsedIDs = []
            return
        }
        let authored = snapshot.componentTree.rows.filter { $0.hasChildren && $0.component.isInitiallyCollapsed }
        collapsedIDs = Set(authored.map(\.id)).subtracting(snapshot.componentRevealHint?.ancestorIDs ?? [])
    }

}
