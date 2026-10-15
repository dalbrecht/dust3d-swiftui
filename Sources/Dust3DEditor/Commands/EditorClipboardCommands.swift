import AppKit
import SwiftUI

/// Focused scene commands defer to the native field editor while text is being edited.
struct EditorClipboardCommands: Commands {
    let pasteboard: EditorPasteboard
    @FocusedValue(\.editorStore) private var store
    @FocusedValue(\.editorTextEditing) private var isEditingText

    private var textView: NSTextView? {
        _ = isEditingText
        _ = pasteboard.textSelectionRevision
        return NSApp.keyWindow?.firstResponder as? NSTextView
    }
    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { route(#selector(NSText.cut(_:))) { store?.copyNodes(cut: true, to: pasteboard) } }
                .keyboardShortcut("x")
                .disabled(
                    textView.map { !$0.isEditable || $0.selectedRange().length == 0 } ?? (store?.canCutNodes != true))
            Button("Copy") { route(#selector(NSText.copy(_:))) { store?.copyNodes(to: pasteboard) } }
                .keyboardShortcut("c")
                .disabled(textView.map { $0.selectedRange().length == 0 } ?? (store?.canCopyNodes != true))
            if let textView {
                Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: textView, from: nil) }
                    .keyboardShortcut("v")
                    .disabled(!textView.isEditable)
            } else {
                NodeClipboardPasteButton(store: store).keyboardShortcut("v")
            }
            Divider()
            Button("Select All") { route(#selector(NSText.selectAll(_:))) { store?.selectAll() } }
                .keyboardShortcut("a")
                .disabled(textView == nil && (store?.snapshot == nil || store?.isWorking != false))

        }
    }
    private func route(_ action: Selector, nodes: () -> Void) {
        if let textView { NSApp.sendAction(action, to: textView, from: nil) } else { nodes() }
    }
}

struct NodeClipboardMenu: View {
    let store: EditorStore
    @Environment(EditorPasteboard.self) private var pasteboard
    var body: some View {
        Menu("Clipboard") {
            Button("Copy Nodes") { store.copyNodes(to: pasteboard) }
                .disabled(!store.canCopyNodes)
                .help("Copies selected nodes, linked profiles and embedded document assets.")
            Button("Cut Editable Nodes") { store.copyNodes(cut: true, to: pasteboard) }
                .disabled(!store.canCutNodes)
                .help("Copies editable selected nodes and embedded assets, then removes those nodes in one undo step.")
            NodeClipboardPasteButton(store: store).accessibilityLabel("Paste Nodes")
        }
        .accessibilityLabel("Node clipboard")
    }
}
