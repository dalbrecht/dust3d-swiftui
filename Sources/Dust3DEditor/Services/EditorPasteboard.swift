import AppKit
import Combine
import Observation

/// App-wide platform boundary; only type availability is polled, and document data is decoded by the session.
@MainActor @Observable final class EditorPasteboard {
    private static let type = NSPasteboard.PasteboardType("org.dust3d.node-clipboard.v1")
    private let pasteboard = NSPasteboard.general
    private(set) var hasNodes = false
    private(set) var textSelectionRevision = 0
    @ObservationIgnored private var selectionObserver: AnyCancellable?
    @ObservationIgnored private var changeCount = -1
    @ObservationIgnored private var watcher: Task<Void, Never>?

    init() {
        refresh()
        selectionObserver = NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)
            .sink { [weak self] _ in self?.textSelectionRevision &+= 1 }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self else { return }
                self.refresh()
            }
        }
    }
    deinit { watcher?.cancel() }

    func read() throws -> Data {
        guard let data = pasteboard.data(forType: Self.type) else { throw PasteboardError.noNodes }
        return data
    }
    func write(_ data: Data) throws {
        let item = NSPasteboardItem()
        guard item.setData(data, forType: Self.type) else { throw PasteboardError.writeFailed }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            refresh()
            throw PasteboardError.writeFailed
        }
        refresh()
    }
    private func refresh() {
        let count = pasteboard.changeCount
        guard count != changeCount else { return }
        changeCount = count
        hasNodes = pasteboard.availableType(from: [Self.type]) != nil
    }
}

enum PasteboardError: Error {
    case noNodes
    case writeFailed
}
