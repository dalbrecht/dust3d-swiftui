import AppKit
import Combine
import Observation

/// App-wide write/text-validation boundary; SwiftUI handles asynchronous paste transfer.
@MainActor @Observable final class EditorPasteboard {
    private static let type = NSPasteboard.PasteboardType(NodeClipboardTransfer.contentType.identifier)
    private let pasteboard = NSPasteboard.general
    private(set) var textSelectionRevision = 0
    @ObservationIgnored private var selectionObserver: AnyCancellable?

    init() {
        selectionObserver = NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)
            .sink { [weak self] _ in self?.textSelectionRevision &+= 1 }
    }

    func write(_ data: Data, snapshotXML: Data) throws {
        let item = NSPasteboardItem()
        // Advertise the immutable snapshot now; AppKit requests its bytes only when a consumer needs them.
        guard
            item.setDataProvider(
                NodeClipboardDataProvider(data: data, snapshotXML: snapshotXML), forTypes: [Self.type, .string])
        else {
            throw PasteboardError.writeFailed
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw PasteboardError.writeFailed }
    }
}

enum PasteboardError: Error {
    case writeFailed
}
