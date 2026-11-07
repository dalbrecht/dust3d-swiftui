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
    var admitsInput: @MainActor () -> Bool = { true }

    var body: some View {
        let invoke = store.componentUngroupAction(target)
        Button(
            ComponentUngroupPresentation.title(wrapperCount: target.wrapperCount),
            action: { if admitsInput() { invoke() } }
        )
        .disabled(!store.canUngroupComponents(target))
        .accessibilityIdentifier("component-ungroup")
        .help(
            "Removes the selected wrappers and their settings, including custom wrapper attributes. Contents keep their order; parts and assets stay. One Undo restores the wrappers."
        )
    }
}
