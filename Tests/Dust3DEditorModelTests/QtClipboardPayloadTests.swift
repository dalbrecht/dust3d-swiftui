import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class QtClipboardPayloadTests: XCTestCase {
    func testQtTextImportsAllSnapshotNodesAndPreservesOpaqueXML() throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 1, y: 2, z: 3), radius: 0.2))
        let payload = try NodeClipboardPayload(snapshotXML: original.modelXML, identifier: "qt-copy")
        XCTAssertEqual(payload.fragment.selectedNodeIDs, ["node"])
        XCTAssertEqual(payload.fragment.document.modelXML, original.modelXML)
        XCTAssertEqual(payload.identifier, "qt-copy")
        XCTAssertEqual(try NodeClipboardPayload(data: payload.encoded()).fragment.selectedNodeIDs, ["node"])
    }

    func testQtTextRejectsEmptySnapshotInvalidGraphAndInvalidToken() throws {
        let empty = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        XCTAssertThrowsError(try NodeClipboardPayload(snapshotXML: empty.modelXML, identifier: "qt"))
        let invalid = Data(
            "<canvas><nodes><node id='x' partId='missing' x='0' y='0' z='0' radius='1'/></nodes></canvas>".utf8)
        XCTAssertThrowsError(try NodeClipboardPayload(snapshotXML: invalid, identifier: "qt"))
        let original = try empty.applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        XCTAssertThrowsError(try NodeClipboardPayload(snapshotXML: original.modelXML, identifier: ""))
        XCTAssertThrowsError(try NodeClipboardPayload(snapshotXML: Data("not xml".utf8), identifier: "qt"))
    }
}
