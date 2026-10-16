import Dust3DDocument
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
