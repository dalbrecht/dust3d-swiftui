import Dust3DKit
import SwiftUI

struct EditorGeometryExportAction {
    let canPerform: Bool
    let perform: @MainActor (DocumentExportFormat) -> Void
}

private struct EditorGeometryExportActionKey: FocusedValueKey { typealias Value = EditorGeometryExportAction }

extension FocusedValues {
    var editorGeometryExportAction: EditorGeometryExportAction? {
        get { self[EditorGeometryExportActionKey.self] }
        set { self[EditorGeometryExportActionKey.self] = newValue }
    }
}

struct EditorGeometryExportCommands: Commands {
    @FocusedValue(\.editorGeometryExportAction) private var action
    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Export OBJ Geometry…") { action?.perform(.obj) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(action?.canPerform != true)
            Button("Export FBX Geometry…") { action?.perform(.fbx) }
                .disabled(action?.canPerform != true)
        }
    }
}
