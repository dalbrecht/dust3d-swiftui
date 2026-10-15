import AppKit
import Dust3DEditorModel
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
            CommandMenu("Canvas") {
                Button("Select All Nodes") { store?.selectAll() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Button("Clear Node Selection") { store?.select(nil) }
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Menu("Transform Selected Nodes") {
                    ForEach(SelectionTransform.allCases, id: \.self) { transform in
                        Button(transform.rawValue) { store?.transformSelection(transform) }
                    }
                }
                .disabled(store?.canTransform != true)
                Button("Reverse Edges Between Selected Nodes") { store?.reverseSelectedEdges() }
                    .disabled(store?.isWorking != false || store?.snapshot?.reversibleEdges.isEmpty != false)
                Divider()
                ForEach(EditingConstraint.allCases, id: \.self) { constraint in
                    Toggle(
                        "Lock \(constraint.rawValue)",
                        isOn: Binding(
                            get: { store?.locks.contains(constraint) == true },
                            set: { store?.setLock(constraint, isLocked: $0) })
                    )
                    .keyboardShortcut(shortcut(for: constraint), modifiers: [.command, .option])
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                }
            }
        }
    }

    private func shortcut(for constraint: EditingConstraint) -> KeyEquivalent {
        switch constraint {
        case .x: "x"
        case .y: "y"
        case .z: "z"
        case .radius: "r"
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
