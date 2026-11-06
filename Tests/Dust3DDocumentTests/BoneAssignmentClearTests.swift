import Dust3DDocument
import Foundation
import XCTest

final class BoneAssignmentClearTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        let xml = Data(
            "<canvas future='retain'><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='e1' partId='p' from='a' to='b' boneName='Root' future='keep'/><edge id='e2' partId='unknown' from='b' to='a' boneName='Hips'/><edge id='e3' from='a' to='b' boneName='Café'/><edge id='e4' from='b' to='a' boneName='Cafe&#769;'/></edges><parts><part id='p' locked='true' visible='false' disabled='true'/></parts><future value='keep'/></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(xml.count)'/><asset name='opaque.bin' offset='\(xml.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + xml + Data([0, 255, 10, 128]))
    }

    func testClearIsOneMetadataUndoAcrossReadonlyAndUnsupportedOwners() throws {
        let original = try source()
        var history = DocumentHistory(document: original)
        try history.apply(.clearEdgeBoneNames(ids: ["e1", "e2", "e3"]))
        let cleared = history.document
        let rows = try cleared.editorContents().edges
        XCTAssertTrue(rows.filter { ["e1", "e2", "e3"].contains($0.id) }.allSatisfy { $0.boneName.isEmpty })
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.id == "e4" }).hasExactBoneName("Cafe\u{301}"))
        XCTAssertEqual(try cleared.editorContents().nodes, try original.editorContents().nodes)
        XCTAssertEqual(try cleared.editorContents().parts, try original.editorContents().parts)
        XCTAssertEqual(cleared.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        let xml = try XMLDocument(data: cleared.modelXML)
        XCTAssertEqual(try xml.nodes(forXPath: "//edge[@future='keep']").count, 1)
        XCTAssertEqual(try xml.nodes(forXPath: "/canvas/future[@value='keep']").count, 1)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), cleared.encoded())
    }

    func testInvalidIDsRejectAtomicallyAndEmptyOrAlreadyClearedKeepRedo() throws {
        let original = try source()
        var history = DocumentHistory(document: original)
        try history.apply(.clearEdgeBoneNames(ids: ["e1"]))
        let cleared = history.document.encoded()
        try history.apply(.clearEdgeBoneNames(ids: ["e1"]))
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.canRedo)
        XCTAssertThrowsError(try history.apply(.clearEdgeBoneNames(ids: ["e1", "missing"]))) {
            XCTAssertEqual($0 as? DocumentError, .invalidNode)
        }
        try history.apply(.clearEdgeBoneNames(ids: []))
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.canRedo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), cleared)
        XCTAssertThrowsError(
            try original.applying(.setEdgeBoneNames(ids: ["e1"], name: "")),
            "Ordinary assignment must retain its editable-owner policy")
    }
}
