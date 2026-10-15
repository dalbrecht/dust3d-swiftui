import AppKit
import SwiftUI

@main
struct Dust3DEditorApp: App {
    @NSApplicationDelegateAdaptor(EditorAppDelegate.self) private var appDelegate
    @FocusedValue(\.editorStore) private var store

    var body: some Scene {
        DocumentGroup(newDocument: EditorFileDocument()) { file in
            EditorRootView(file: file.$document)
                .id(file.document.identity)
        }
        .defaultSize(width: 1300, height: 820)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store?.undo() }
                    .keyboardShortcut("z")
                    .disabled(store?.canUndo != true)
                Button("Redo") { store?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(store?.canRedo != true)
            }
        }
    }
}

@MainActor
final class EditorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct EditorStoreKey: FocusedValueKey { typealias Value = EditorStore }

extension FocusedValues {
    var editorStore: EditorStore? {
        get { self[EditorStoreKey.self] }
        set { self[EditorStoreKey.self] = newValue }
    }
}
