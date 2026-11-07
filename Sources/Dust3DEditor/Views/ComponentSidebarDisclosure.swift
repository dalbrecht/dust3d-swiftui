import Dust3DEditorModel
import Foundation
import Observation

/// Component disclosure belongs to the sidebar; reveal never changes graph or component selection.
@MainActor @Observable final class ComponentSidebarDisclosure {
    private(set) var epoch = UUID()
    var collapsedIDs: Set<String> {
        didSet { if oldValue != collapsedIDs { epoch = UUID() } }
    }
    init(collapsedIDs: Set<String> = []) { self.collapsedIDs = collapsedIDs }
    func reveal(_ hint: ComponentRevealHint) { collapsedIDs.subtract(hint.ancestorIDs) }
}
