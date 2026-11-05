import Dust3DEditorModel
import SwiftUI

/// Counts every explicit wrapper; selected descendants are not coalesced with their ancestors.
enum ComponentUngroupPresentation {
    static func title(wrapperCount: Int) -> String {
        if wrapperCount == 1 { return "Ungroup Component" }
        if wrapperCount > 1 { return "Ungroup \(wrapperCount) Components" }
        return "Ungroup"
    }
}

/// One native action for both singleton and multi-row contextual/inspector intents.
struct ComponentUngroupButton: View {
    let store: EditorStore
    let target: ComponentUngroupTarget
    var body: some View {
        Button(
            ComponentUngroupPresentation.title(wrapperCount: target.wrapperCount),
            action: store.componentUngroupAction(target)
        )
        .disabled(!store.canUngroupComponents(target))
        .accessibilityIdentifier("component-ungroup")
        .help(
            "Removes the selected wrappers and their settings, including custom wrapper attributes. Contents keep their order; parts and assets stay. One Undo restores the wrappers."
        )
    }
}
