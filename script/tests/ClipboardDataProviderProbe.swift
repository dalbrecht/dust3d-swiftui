import AppKit

@main struct ProviderProbe {
    static func main() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("org.dust3d.node-clipboard.v1")
        let data = Data(repeating: 0xA5, count: 32 * 1024 * 1024)
        let item = NSPasteboardItem()
        weak var releasedReference: NodeClipboardDataProvider?
        do {
            let provider = NodeClipboardDataProvider(data: data)
            releasedReference = provider
            precondition(item.setDataProvider(provider, forTypes: [type]))
            precondition(board.writeObjects([item]))
        }
        precondition(releasedReference != nil, "AppKit must retain the promise after the writer returns")
        precondition(board.availableType(from: [type]) == type)
        precondition(board.data(forType: type) == data, "Promised bytes must exactly match the copied snapshot")
        print("PASS: 32 MiB promised data retained and delivered exactly")
    }
}
