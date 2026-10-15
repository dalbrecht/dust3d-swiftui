import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ClipboardPayloadTests: XCTestCase {
    private func fragment() throws -> NodeClipboard {
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        return try document.copyingNodes(["a"])
    }
    private func transport(_ header: [String: Any], archive: Data? = nil) throws -> Data {
        let metadata = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        var result = Data("Dust3D-Node-Clipboard\n".utf8)
        for shift in [24, 16, 8, 0] { result.append(UInt8((metadata.count >> shift) & 255)) }
        result.append(metadata)
        result.append(try archive ?? fragment().document.encoded())
        return result
    }
    func testTransportRoundTripIsDeterministicAndRebasesSlices() throws {
        let copied = try fragment()
        let payload = try NodeClipboardPayload(fragment: copied, identifier: "copy")
        let data = try payload.encoded()
        XCTAssertEqual(try payload.encoded(), data)
        let decoded = try NodeClipboardPayload(data: (Data([1, 2, 3]) + data).dropFirst(3))
        XCTAssertEqual(decoded.fragment.document.encoded(), copied.document.encoded())
        XCTAssertEqual(decoded.fragment.selectedNodeIDs, ["a"])
        XCTAssertEqual(decoded.identifier, "copy")
        XCTAssertThrowsError(try NodeClipboardPayload(fragment: copied, identifier: ""))
        XCTAssertThrowsError(try NodeClipboardPayload(fragment: copied, identifier: String(repeating: "x", count: 129)))
    }
    func testMalformedTransportAndMetadataRejectBeforeEditing() throws {
        var malformedData = [Data(), Data("not a clipboard".utf8)]
        let invalidSuffixes: [[UInt8]] = [
            [0, 0, 0, 0, 0], [255, 255, 255, 255, 0], [0, 0, 0, 50, 0], [0, 0, 0, 1, 255],
        ]
        for suffix in invalidSuffixes {
            var data = Data("Dust3D-Node-Clipboard\n".utf8)
            data.append(contentsOf: suffix)
            malformedData.append(data)
        }
        for data in malformedData {
            XCTAssertThrowsError(try NodeClipboardPayload(data: data)) {
                XCTAssertEqual($0 as? ClipboardError, .invalidPayload)
            }
        }
        let valid: [String: Any] = ["version": 1, "identifier": "copy", "selectedIDs": ["a"]]
        var variants: [[String: Any]] = []
        for ids in [[], ["a", "a"], [""], [String(repeating: "x", count: 129)], Array(repeating: "a", count: 10_001)] {
            var header = valid
            header["selectedIDs"] = ids
            variants.append(header)
        }
        for id in ["", String(repeating: "x", count: 129)] {
            var header = valid
            header["identifier"] = id
            variants.append(header)
        }
        var malformed = valid
        malformed.removeValue(forKey: "version")
        variants.append(malformed)
        for header in variants {
            XCTAssertThrowsError(try NodeClipboardPayload(data: transport(header))) {
                XCTAssertEqual($0 as? ClipboardError, .invalidPayload)
            }
        }
        var future = valid
        future["version"] = 2
        XCTAssertThrowsError(try NodeClipboardPayload(data: transport(future))) {
            XCTAssertEqual($0 as? ClipboardError, .unsupportedVersion)
        }
        XCTAssertThrowsError(try NodeClipboardPayload(data: transport(valid, archive: Data())))
        var missing = valid
        missing["selectedIDs"] = ["missing"]
        XCTAssertThrowsError(try NodeClipboardPayload(data: transport(missing)))
    }
    func testEncodingBoundsSelectionMetadataBeforeAppendingArchive() throws {
        let quoted = String(repeating: "&quot;", count: 120)
        let nodes = (0..<10_000).map { "<node id='\(quoted)\($0)' partId='p' x='0' y='0' z='0' radius='.1'/>" }.joined()
        let model = Data("<canvas><nodes>\(nodes)</nodes><parts><part id='p'/></parts></canvas>".utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let document = try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
        let fragment = try NodeClipboard(
            document: document, selectedNodeIDs: Set(try document.editorContents().nodes.map(\.id)))
        let payload = try NodeClipboardPayload(fragment: fragment, identifier: "large-selection")
        XCTAssertThrowsError(try payload.encoded()) { XCTAssertEqual($0 as? DocumentError, .limitExceeded) }
    }

}
