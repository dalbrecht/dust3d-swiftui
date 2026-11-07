import Dust3DEditorModel
import SwiftUI

@MainActor struct GraphSelectionMenuActions {
    struct Entry {
        let action: GraphSelectionAction
        let invoke: @MainActor () -> Void
    }
    let entries: [Entry]

    init(store: EditorStore?, admitsInput: @escaping @MainActor () -> Bool = { true }) {
        guard let store, let snapshot = store.snapshot else {
            entries = []
            return
        }
        entries = GraphSelectionAction.allCases.compactMap { action in
            let target = GraphSelectionActionTarget(snapshot: snapshot, action: action)
            guard store.canPerformGraphSelectionAction(target) else { return nil }
            let invoke = store.graphSelectionAction(target)
            return Entry(action: action) { if admitsInput() { invoke() } }
        }
    }
}

/// Contextual items supplement the existing Canvas menu and inspector controls.
struct GraphSelectionMenu: View {
    let actions: GraphSelectionMenuActions
    var body: some View {
        if !actions.entries.isEmpty {
            Menu("Edit Graph Selection") {
                ForEach(actions.entries, id: \.action) { entry in
                    if entry.action.isDestructive {
                        Button(entry.action.title, role: .destructive, action: entry.invoke)
                    } else {
                        Button(entry.action.title, action: entry.invoke)
                    }
                }
            }
        }
    }
}
