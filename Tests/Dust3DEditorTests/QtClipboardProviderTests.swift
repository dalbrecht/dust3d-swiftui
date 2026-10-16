import AppKit
import XCTest

@testable import Dust3DEditor

final class QtClipboardProviderTests: XCTestCase {
    @MainActor func testProviderKeepsNativeAndTextRepresentationsDistinct() {
        let native = Data([1, 2, 3])
        let xml = Data("<canvas/>".utf8)
        let provider = NodeClipboardDataProvider(data: native, snapshotXML: xml)
        let item = NSPasteboardItem()
        let nativeType = NSPasteboard.PasteboardType(NodeClipboardTransfer.contentType.identifier)
        provider.pasteboard(nil, item: item, provideDataForType: nativeType)
        provider.pasteboard(nil, item: item, provideDataForType: .string)
        XCTAssertEqual(item.data(forType: nativeType), native)
        XCTAssertEqual(item.string(forType: .string), "<canvas/>")
        provider.pasteboard(nil, item: item, provideDataForType: .png)
        XCTAssertNil(item.data(forType: .png))
    }
}
