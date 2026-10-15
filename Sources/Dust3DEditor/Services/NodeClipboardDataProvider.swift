import AppKit

/// AppKit retains the provider for the lifetime of its promise, independently of the source window.
final class NodeClipboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    private let data: Data

    init(data: Data) { self.data = data }

    nonisolated func pasteboard(
        _ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType
    ) {
        item.setData(data, forType: type)
    }
}
