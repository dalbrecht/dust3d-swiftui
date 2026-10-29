import SwiftUI

struct EditorOBJExportAction {
    let canPerform: Bool
    let perform: @MainActor () -> Void
}

private struct EditorOBJExportActionKey: FocusedValueKey { typealias Value = EditorOBJExportAction }

extension FocusedValues {
    var editorOBJExportAction: EditorOBJExportAction? {
        get { self[EditorOBJExportActionKey.self] }
        set { self[EditorOBJExportActionKey.self] = newValue }
    }
}

struct EditorOBJExportCommands: Commands {
    @FocusedValue(\.editorOBJExportAction) private var action
    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Export OBJ Geometry…") { action?.perform() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(action?.canPerform != true)
        }
    }
}
