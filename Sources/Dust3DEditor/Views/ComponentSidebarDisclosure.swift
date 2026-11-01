import Dust3DEditorModel
import Observation

/// Component disclosure belongs to the sidebar; reveal never changes graph or component selection.
@MainActor @Observable final class ComponentSidebarDisclosure {
    var collapsedIDs: Set<String>
    init(collapsedIDs: Set<String> = []) { self.collapsedIDs = collapsedIDs }
    func reveal(_ hint: ComponentRevealHint) { collapsedIDs.subtract(hint.ancestorIDs) }
}
