import Dust3DEditorModel
import SwiftUI

enum ComponentDeletionPresentation {
    static func title(rootCount: Int) -> String {
        switch rootCount {
        case 1: return "Delete Component and Contents"
        case 2...: return "Delete \(rootCount) Components and Contents"
        default: return "Delete Components and Contents"
        }
    }
}

/// Explicit management deletion is undoable and does not inherit canvas lock restrictions.
struct ComponentDeletionButton: View {
    let store: EditorStore
    let target: ComponentDeletionTarget

    var body: some View {
        Button(
            ComponentDeletionPresentation.title(rootCount: target.rootCount), role: .destructive,
            action: store.componentDeletionAction(target)
        )
        .disabled(!store.canDeleteComponentSubtrees(target))
        .accessibilityIdentifier("component-delete")
        .help(
            "Delete these components and their contents, including hidden, disabled or locked parts. Shared parts used elsewhere are kept. Undo restores deleted content."
        )
    }
}
