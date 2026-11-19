import Dust3DDocument
import Foundation
import XCTest

final class AuthoredGroupNameTests: XCTestCase {
    func testCopiedCapsuleGroupNameSurvivesReorderReopenAndExactUndo() throws {
        let fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let capsule = try Dust3DDocument(data: Data(contentsOf: fixture))
        let linked = try XCTUnwrap(try capsule.components().first)
        let source = String(decoding: capsule.modelXML, as: UTF8.self)
            .replacingOccurrences(of: "</components>", with: "<component id='existing' name='Keep'/></components>")
        let model = Data(source.utf8)
        let opaque = Data([1, 0, 255])
        let header = Data(
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='\(opaque.count)'/></ds3>"
                .utf8)
        let prefix = Data("DUST3D 1.0 xml \(String(format: "%010d", 26 + header.count))\n".utf8)
        let original = try Dust3DDocument(data: prefix + header + model + opaque)
        var history = DocumentHistory(document: original)

        try history.apply(.groupComponents(ids: [linked.id], groupID: "new-group"))
        let grouped = history.document
        XCTAssertEqual(try grouped.components().first?.name, "Group 2")
        XCTAssertEqual(try grouped.components().first?.childIDs, [linked.id])
        try history.apply(.reorderComponent(id: "new-group", direction: .last))
        let reordered = try Dust3DDocument(data: history.document.encoded())
        let rows = try reordered.components()
        XCTAssertEqual(rows.map(\.id), ["existing", "new-group", linked.id])
        XCTAssertEqual(rows.map(\.name), ["Keep", "Group 2", linked.name])
        XCTAssertEqual(reordered.asset(named: "opaque.bin"), opaque)

        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), grouped.encoded())
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
    }
}
