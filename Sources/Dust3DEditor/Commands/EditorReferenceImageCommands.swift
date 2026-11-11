import AppKit
import SwiftUI

struct ReferenceImageMenuActions {
    let compose: @MainActor () -> Void
    let clearArtwork: (@MainActor () -> Void)?
    let remove: (@MainActor () -> Void)?
}

private struct EditorReferenceImageActionsKey: FocusedValueKey {
    typealias Value = ReferenceImageMenuActions
}

extension FocusedValues {
    var editorReferenceImageActions: ReferenceImageMenuActions? {
        get { self[EditorReferenceImageActionsKey.self] }
        set { self[EditorReferenceImageActionsKey.self] = newValue }
    }
}

struct EditorReferenceImageCommands: Commands {
    @FocusedValue(\.editorReferenceImageActions) private var actions

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            let window = NSApp.keyWindow
            let capturedActions = actions
            let admitsWindow: @MainActor () -> Bool = {
                guard let window, NSApp.keyWindow === window else { return false }
                return window.attachedSheet == nil && window.sheetParent == nil && NSApp.modalWindow == nil
            }
            Button("Compose Reference Image…") {
                guard admitsWindow() else { return }
                capturedActions?.compose()
            }
            .disabled(capturedActions == nil || !admitsWindow())
            Button("Clear Reference Artwork") {
                guard admitsWindow() else { return }
                capturedActions?.clearArtwork?()
            }
            .disabled(capturedActions?.clearArtwork == nil || !admitsWindow())
            Button("Remove Reference Image", role: .destructive) {
                guard admitsWindow() else { return }
                capturedActions?.remove?()
            }
            .disabled(capturedActions?.remove == nil || !admitsWindow())
        }
    }
}
