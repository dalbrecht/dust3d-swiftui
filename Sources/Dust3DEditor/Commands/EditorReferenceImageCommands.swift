import AppKit
import SwiftUI

struct EditorReferenceImageActions {
    enum Action {
        case compose
        case importImage
        case remove
    }

    let canRemove: Bool
    let perform: @MainActor (Action) -> Void
}

private struct EditorReferenceImageActionsKey: FocusedValueKey {
    typealias Value = EditorReferenceImageActions
}

extension FocusedValues {
    var editorReferenceImageActions: EditorReferenceImageActions? {
        get { self[EditorReferenceImageActionsKey.self] }
        set { self[EditorReferenceImageActionsKey.self] = newValue }
    }
}

struct EditorReferenceImageButtons: View {
    let canBegin: Bool
    let canRemove: Bool
    let perform: @MainActor (EditorReferenceImageActions.Action) -> Void

    var body: some View {
        Button("Compose Reference Image…") { perform(.compose) }
            .disabled(!canBegin)
        Button("Import Reference Image…") { perform(.importImage) }
            .disabled(!canBegin)
        Button("Remove Reference Image", role: .destructive) { perform(.remove) }
            .disabled(!canRemove)
    }
}

struct EditorReferenceImageCommands: Commands {
    @FocusedValue(\.editorReferenceImageActions) private var actions

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            let window = NSApp.keyWindow
            let actions = actions
            let canBegin = actions != nil && admits(window)
            Menu("Reference Image") {
                EditorReferenceImageButtons(canBegin: canBegin, canRemove: canBegin && actions?.canRemove == true) {
                    guard admits(window) else { return }
                    actions?.perform($0)
                }
            }
            .disabled(!canBegin)
        }
    }

    private func admits(_ window: NSWindow?) -> Bool {
        guard let window, NSApp.keyWindow === window else { return false }
        return window.attachedSheet == nil && window.sheetParent == nil && NSApp.modalWindow == nil
    }
}
