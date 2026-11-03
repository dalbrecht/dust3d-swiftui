import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct ComponentOrderMenu: View {
    let store: EditorStore

    var body: some View {
        Menu("Reorder Component") {
            ForEach(ComponentOrderMove.allCases, id: \.self) { direction in
                Button(title(direction)) { store.reorderComponent(direction) }
                    .disabled(!store.canReorderComponent(direction))
            }
        }
        .accessibilityLabel("Reorder component among siblings")
        .disabled(store.isWorking || store.snapshot?.selectedComponentID == nil)
        .help("Changes order within this parent in one undo step. Component order can affect mesh combination.")
    }

    private func title(_ direction: ComponentOrderMove) -> String {
        switch direction {
        case .up: "Move Up"
        case .down: "Move Down"
        case .first: "Move to Top"
        case .last: "Move to Bottom"
        }
    }
}

/// Keyboard-accessible placement at either boundary of the current sibling list.
struct ComponentBatchOrderMenu: View {
    let store: EditorStore
    let snapshot: EditorSnapshot

    var body: some View {
        if let target = ComponentPlacementTarget(snapshot: snapshot) {
            let components = snapshot.componentTree.rows.map(\.component)
            if let firstSelected = components.first(where: { snapshot.selectedComponentIDs.contains($0.id) }),
                let firstSibling = components.first(where: { $0.parentID == firstSelected.parentID })
            {
                let top = ComponentDropPlacement.before(firstSibling.id)
                let bottom = ComponentDropPlacement.end(parentID: firstSelected.parentID)
                Menu("Reorder Selected Components") {
                    placementButton("Move to Top", placement: top, target: target)
                    placementButton("Move to Bottom", placement: bottom, target: target)
                }
                .disabled(store.isWorking)
                .help("Moves the selected components together within their parent.")
            }
        }
    }

    private func placementButton(
        _ title: LocalizedStringKey, placement: ComponentDropPlacement, target: ComponentPlacementTarget
    ) -> some View {
        Button(title) { store.placeComponents(at: placement, target: target) }
            .disabled(!target.canPlace(at: placement, in: snapshot))
    }
}
