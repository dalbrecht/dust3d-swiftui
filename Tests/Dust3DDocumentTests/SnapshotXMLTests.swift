import Dust3DDocument
import Foundation
import XCTest

final class SnapshotXMLTests: XCTestCase {
    private let snapshot = """
        <?xml version="1.0" encoding="UTF-8"?>
        <canvas originX="0" originY="0" originZ="0" future="retained">
          <nodes><node id="a" partId="p" x="1" y="2" z="3" radius="0.1"/></nodes>
          <edges/>
          <parts><part id="p" visible="true"/></parts>
          <components><component id="c" linkDataType="partId" linkData="p"/></components>
          <extension opaque="yes"/>
        </canvas>
        """

    func testSnapshotXMLCreatesValidatedArchiveWithoutChangingXMLBytes() throws {
        let bytes = Data(snapshot.utf8)
        let document = try Dust3DDocument(snapshotXML: bytes)
        XCTAssertEqual(document.modelXML, bytes)
        XCTAssertEqual(try document.node(id: "a").position, .init(x: 1, y: 2, z: 3))
        let reopened = try Dust3DDocument(data: document.encoded())
        XCTAssertEqual(reopened.modelXML, bytes)
        let fragment = try NodeClipboard(document: reopened, selectedNodeIDs: ["a"])
        XCTAssertEqual(fragment.identifiers, ["a", "p", "c"])
        XCTAssertNil(reopened.asset(named: "canvas.png"))
        XCTAssertEqual(try Dust3DDocument(snapshotXML: (Data([0]) + bytes).dropFirst()).modelXML, bytes)
    }

    func testInvalidOrOversizedSnapshotXMLRejectsAtTheBoundary() throws {
        for xml in [
            "", "<canvas>", "<other/>",
            "<!DOCTYPE canvas [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><canvas>&x;</canvas>",
            snapshot.replacingOccurrences(of: "<edges/>", with: "<nodes><node id='a'/></nodes>"),
            snapshot.replacingOccurrences(of: "radius=\"0.1\"", with: "radius=\"-1\""),
            snapshot.replacingOccurrences(of: "x=\"1\"", with: "x=\"nan\""),
        ] {
            XCTAssertThrowsError(try Dust3DDocument(snapshotXML: Data(xml.utf8)))
        }
        XCTAssertThrowsError(try Dust3DDocument(snapshotXML: Data(repeating: 32, count: 16 * 1024 * 1024 + 1))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        let deep =
            "<canvas>" + String(repeating: "<x>", count: 129) + String(repeating: "</x>", count: 129) + "</canvas>"
        XCTAssertThrowsError(try Dust3DDocument(snapshotXML: Data(deep.utf8)))
    }
}
