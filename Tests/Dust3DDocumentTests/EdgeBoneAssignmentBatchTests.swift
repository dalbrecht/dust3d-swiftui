import Dust3DDocument
import Foundation
import XCTest

final class EdgeBoneAssignmentBatchTests: XCTestCase {
    private func source(qFlags: String = "", omitOwner: Bool = false, aliasOwner: Bool = false) throws -> Dust3DDocument
    {
        let firstOwner = omitOwner ? "" : "partId='p'"
        let secondOwner = aliasOwner ? "café" : "q"
        let model = Data(
            "<canvas><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='c' partId='q' x='.3' y='.5' z='.5' radius='.1'/><node id='d' partId='q' x='.4' y='.5' z='.5' radius='.1'/><node id='x' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='e1' from='a' to='b' \(firstOwner) boneName='Café' future='keep'/><edge id='e2' from='c' to='d' partId='\(secondOwner)' boneName='Cafe&#769;'/><edge id='e3' from='b' to='x' partId='p' boneName='Other'/></edges><parts><part id='p'/><part id='q' \(qFlags)/><part id='cafe&#769;'/></parts><future value='retain'/></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testBatchAssignClearAndHistoryPreserveExactAssetsAndUnselectedEdges() throws {
        let original = try source()
        var history = DocumentHistory(document: original)
        let name = " 左腕 & <hand> "
        try history.apply(.setEdgeBoneNames(ids: ["e1", "e2"], name: name))
        let bound = history.document
        let rows = try bound.editorContents().edges
        XCTAssertTrue(rows.filter { ["e1", "e2"].contains($0.id) }.allSatisfy { $0.hasExactBoneName(name) })
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.id == "e3" }).hasExactBoneName("Other"))
        XCTAssertEqual(try bound.editorContents().nodes, try original.editorContents().nodes)
        XCTAssertEqual(bound.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        let xml = try XMLDocument(data: bound.modelXML)
        XCTAssertEqual(try xml.nodes(forXPath: "//edge[@future='keep']").count, 1)
        XCTAssertEqual(try xml.nodes(forXPath: "/canvas/future[@value='retain']").count, 1)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), bound.encoded())
        try history.apply(.setEdgeBoneNames(ids: ["e1", "e2"], name: ""))
        XCTAssertTrue(
            try history.document.editorContents().edges.filter { ["e1", "e2"].contains($0.id) }.allSatisfy {
                $0.boneName.isEmpty
            })
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), bound.encoded())
    }

    func testInvalidNamesReadonlyOwnersAndAliasesRejectWithoutPartialChangesOrRedoLoss() throws {
        for original in [
            try source(), try source(qFlags: "locked='true'"), try source(qFlags: "visible='false'"),
            try source(qFlags: "disabled='true'"), try source(aliasOwner: true),
        ] {
            var history = DocumentHistory(document: original)
            try history.apply(.setEdgeBoneName(id: "e3", name: "Temporary"))
            XCTAssertTrue(history.undo())
            let before = history.document.encoded()
            for command: DocumentCommand in [
                .setEdgeBoneNames(ids: ["e1", "e2"], name: "bad\nname"),
                .setEdgeBoneNames(ids: ["e1", "missing"], name: "Root"),
            ] {
                XCTAssertThrowsError(try history.apply(command))
                XCTAssertEqual(history.document.encoded(), before)
                XCTAssertTrue(history.canRedo)
            }
            if original.encoded() != (try source()).encoded() {
                XCTAssertThrowsError(try history.apply(.setEdgeBoneNames(ids: ["e1", "e2"], name: "Root"))) {
                    XCTAssertEqual($0 as? DocumentError, .invalidNode)
                }
                XCTAssertEqual(history.document.encoded(), before)
                XCTAssertTrue(history.canRedo)
            }
        }
    }

    func testLegacyAbsentOwnerExactUnicodeAndNoOpCommandsKeepRedo() throws {
        let original = try source(omitOwner: true)
        var history = DocumentHistory(document: original)
        let decomposed = "Cafe\u{301}"
        try history.apply(.setEdgeBoneNames(ids: ["e1", "e2"], name: decomposed))
        XCTAssertNotEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(
            try history.document.editorContents().edges.filter { ["e1", "e2"].contains($0.id) }.allSatisfy {
                $0.hasExactBoneName(decomposed)
            })
        XCTAssertTrue(history.undo())
        try history.apply(.setEdgeBoneNames(ids: ["e3"], name: "Other"))
        try history.apply(.setEdgeBoneNames(ids: [], name: "Root"))
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.canRedo)
        XCTAssertFalse(history.canUndo)
    }
}
