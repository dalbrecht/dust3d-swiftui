import AppKit

/// AppKit retains the provider for the lifetime of its promise, independently of the source window.
final class NodeClipboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    private let representations: [NSPasteboard.PasteboardType: Data]

    init(data: Data, snapshotXML: Data) {
        representations = [
            NSPasteboard.PasteboardType(NodeClipboardTransfer.contentType.identifier): data,
            .string: snapshotXML,
        ]
    }

    nonisolated func pasteboard(
        _ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard let data = representations[type] else { return }
        item.setData(data, forType: type)
    }
}
