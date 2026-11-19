import AppKit
import SwiftUI

struct EditorReferenceImageActions {
    enum Action {
        case compose
        case importImage
        case clearArtwork
        case remove
    }

    var canClearArtwork: Bool = false
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
    var canClearArtwork: Bool = false
    let perform: @MainActor (EditorReferenceImageActions.Action) -> Void

    var body: some View {
        Button("Compose Reference Image…") { perform(.compose) }
            .disabled(!canBegin)
        Button("Import Reference Image…") { perform(.importImage) }
            .disabled(!canBegin)
        Button("Clear Reference Artwork") { perform(.clearArtwork) }
            .disabled(!canBegin || !canClearArtwork)
            .help("Clear the image while keeping its dimensions and canvas alignment. You can undo this.")
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
                EditorReferenceImageButtons(
                    canBegin: canBegin, canRemove: canBegin && actions?.canRemove == true,
                    canClearArtwork: canBegin && actions?.canClearArtwork == true
                ) {
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
