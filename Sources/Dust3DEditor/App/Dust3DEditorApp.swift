import AppKit
import Dust3DEditorModel
import SwiftUI

@main
struct Dust3DEditorApp: App {
    @NSApplicationDelegateAdaptor(EditorAppDelegate.self) private var appDelegate
    @FocusedValue(\.editorStore) private var store
    @State private var pasteboard = EditorPasteboard()

    var body: some Scene {
        DocumentGroup(newDocument: EditorFileDocument()) { file in
            EditorRootView(file: file.$document)
                .environment(pasteboard)
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
            EditorClipboardCommands(pasteboard: pasteboard)
            CommandMenu("Canvas") {
                Toggle(
                    "Move Origin",
                    isOn: Binding(get: { store?.isMovingOrigin == true }, set: { store?.setMovingOrigin($0) })
                )
                .disabled(store?.isWorking != false || store?.snapshot?.origin == nil)
                Button("Center Origin on Model") { store?.centerOriginOnModel() }
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Button("Cancel Origin Move") { store?.cancelOriginDrag() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(store?.isMovingOrigin != true)
                Divider()
                Button("Select All Nodes") { store?.selectAll() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Button("Clear Selection") { store?.select(nil) }
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Menu("Transform Selected Nodes") {
                    ForEach(SelectionTransform.allCases, id: \.self) { transform in
                        Button(transform.rawValue) { store?.transformSelection(transform) }
                            .disabled(transform.usesOrigin && store?.snapshot?.origin == nil)
                    }
                }
                .disabled(store?.canTransform != true)
                DescendantRotationMenu(store: store)
                Button("Reverse Edges Between Selected Nodes") { store?.reverseSelectedEdges() }
                    .disabled(store?.isWorking != false || store?.snapshot?.reversibleEdges.isEmpty != false)
                Button("Reverse Selected Edge") {
                    if let id = store?.snapshot?.selectedEdgeID { store?.reverseEdge(id) }
                }
                .disabled(store?.isWorking != false || store?.snapshot?.canEditSelectedEdge != true)
                Button("Delete Selected Edge") { store?.deleteSelection() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(store?.isWorking != false || store?.snapshot?.canEditSelectedEdge != true)
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

private struct EditorTextEditingKey: FocusedValueKey { typealias Value = Bool }

private struct EditorStoreKey: FocusedValueKey { typealias Value = EditorStore }

extension FocusedValues {
    var editorTextEditing: Bool? {
        get { self[EditorTextEditingKey.self] }
        set { self[EditorTextEditingKey.self] = newValue }
    }

    var editorStore: EditorStore? {
        get { self[EditorStoreKey.self] }
        set { self[EditorStoreKey.self] = newValue }
    }
}
