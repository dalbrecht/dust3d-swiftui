import AppKit
import SwiftUI

/// Focused scene commands defer to the native field editor while text is being edited.
struct EditorClipboardCommands: Commands {
    let pasteboard: EditorPasteboard
    @FocusedValue(\.editorStore) private var store
    @FocusedValue(\.editorTextEditing) private var isEditingText
    @FocusedValue(\.editorAnimationFocus) private var isAnimationFocused
    @FocusedValue(\.editorComponentSidebarFocus) private var isComponentSidebarFocused
    @FocusedValue(\.editorComponentSidebarSelectAll) private var sidebarSelectAll
    @FocusedValue(\.editorEdgeSidebarSelectAll) private var edgeSidebarSelectAll

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
                    textView.map { !$0.isEditable || $0.selectedRange().length == 0 }
                        ?? (isAnimationFocused == true || store?.canCutNodes != true))
            Button("Copy") { route(#selector(NSText.copy(_:))) { store?.copyNodes(to: pasteboard) } }
                .keyboardShortcut("c")
                .disabled(
                    textView.map { $0.selectedRange().length == 0 }
                        ?? (isAnimationFocused == true || store?.canCopyNodes != true))
            if let textView {
                Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: textView, from: nil) }
                    .keyboardShortcut("v")
                    .disabled(!textView.isEditable)
            } else {
                NodeClipboardPasteButton(store: store).keyboardShortcut("v")
            }
            Button("Paste Nodes from Qt XML File…") { store?.chooseQtXMLFile() }
                .disabled(store?.canChooseQtXMLFile != true)
            Divider()
            Button("Select All", action: selectAll)
                .keyboardShortcut("a")
                .disabled(!canSelectAll)
        }
    }

    private var selectAllDestination: EditorCommandScope.SelectAllDestination {
        EditorCommandScope.selectAllDestination(
            nativeTextFocus: textView != nil, componentSidebarFocus: isComponentSidebarFocused == true,
            animationFocus: isAnimationFocused == true, edgeSidebarFocus: edgeSidebarSelectAll != nil)
    }

    private var canSelectAll: Bool {
        switch selectAllDestination {
        case .text: true
        case .components:
            sidebarSelectAll.map { store?.canSelectAllVisibleComponents($0) == true } ?? false
        case .edges:
            edgeSidebarSelectAll.map { store?.canSelectAllSidebarEdges($0) == true } ?? false
        case .graph: store?.canSave == true
        case .unavailable: false
        }
    }

    private func selectAll() {
        guard canSelectAll else { return }
        switch selectAllDestination {
        case .text:
            if let textView { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: textView, from: nil) }
        case .components:
            if let sidebarSelectAll { store?.selectAllVisibleComponents(sidebarSelectAll) }
        case .edges:
            if let edgeSidebarSelectAll { store?.selectAllSidebarEdges(edgeSidebarSelectAll) }
        case .graph: store?.selectAll()
        case .unavailable: break
        }
    }

    private func route(_ action: Selector, nodes: () -> Void) {
        if let textView {
            NSApp.sendAction(action, to: textView, from: nil)
        } else if EditorCommandScope.allowsGraphShortcuts(
            animationFocus: isAnimationFocused == true, nativeTextFocus: false)
        {
            nodes()
        }
    }
}

struct NodeClipboardMenu: View {
    let store: EditorStore
    @Environment(EditorPasteboard.self) private var pasteboard
    var body: some View {
        Menu("Clipboard") {
            Button("Copy Nodes") { store.copyNodes(to: pasteboard) }
                .disabled(!store.canCopyNodes)
                .help(
                    "Native copies include nodes, linked profiles and assets. The Qt text fallback contains graph XML only."
                )
            Button("Cut Editable Nodes") { store.copyNodes(cut: true, to: pasteboard) }
                .disabled(!store.canCutNodes)
                .help(
                    "Copies editable nodes and assets before deleting in one undo step. Qt text transfers graph XML only."
                )
            NodeClipboardPasteButton(store: store).accessibilityLabel("Paste Nodes")
        }
        .accessibilityLabel("Node clipboard")
    }
}
