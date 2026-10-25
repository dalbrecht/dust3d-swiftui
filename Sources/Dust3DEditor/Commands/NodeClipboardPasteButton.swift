import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// The system loads the representation asynchronously; only copied Data crosses into the editing session.
struct NodeClipboardTransfer: Transferable, Sendable {
    let data: Data
    var isQtText = false
    static let contentType = UTType(exportedAs: "org.dust3d.node-clipboard.v1", conformingTo: .data)
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: contentType) { data in NodeClipboardTransfer(data: data) }
        DataRepresentation(importedContentType: .utf8PlainText) { data in
            NodeClipboardTransfer(data: data, isQtText: true)
        }
    }
}

struct NodeClipboardPasteButton: View {
    @FocusedValue(\.editorAnimationFocus) private var isAnimationFocused
    let store: EditorStore?
    var body: some View {
        PasteButton(payloadType: NodeClipboardTransfer.self) { values in
            guard
                EditorCommandScope.allowsGraphShortcuts(
                    animationFocus: isAnimationFocused == true, nativeTextFocus: false),
                let value = values.first
            else { return }
            if value.isQtText {
                store?.pasteQtNodes(snapshotXML: value.data)
            } else {
                store?.pasteNodes(data: value.data)
            }
        }
        .disabled(isAnimationFocused == true || store?.snapshot == nil || store?.isWorking != false)
    }
}
