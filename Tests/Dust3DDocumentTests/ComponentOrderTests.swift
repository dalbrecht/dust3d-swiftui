import Dust3DDocument
import Foundation
import XCTest

final class ComponentOrderTests: XCTestCase {
    private func document(
        _ components: String =
            "<component id='a' future='group'><component id='c'/><future value='kept'/><component id='e'/><!--nested--><component id='f'/></component><!--root--><future value='root'/><component id='b' linkDataType='partId' linkData='p' name='Body'/><component id='d' linkDataType='opaque' linkData='future'/>",
        nodes: String = "<node id='n' partId='p' x='1' y='2' z='3' radius='.1' future='node'/>"
    ) throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='canvas'><nodes>\(nodes)</nodes><parts><part id='p' locked='true' visible='false' disabled='true'/></parts><components>\(components)</components></canvas>"
                .utf8)
        let header =
            "<ds3 future='archive'><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4' future='asset'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
    func testEveryOrderMoveReordersOnlySiblingsAndRetainsComponentSubtrees() throws {
        let original = try document()
        for (direction, expected) in [
            (ComponentOrderMove.up, ["b", "a", "d"]), (.down, ["a", "d", "b"]), (.first, ["b", "a", "d"]),
            (.last, ["a", "d", "b"]),
        ] {
            let changed = try original.applying(.reorderComponent(id: "b", direction: direction))
            let components = try changed.components()
            XCTAssertEqual(components.filter { $0.parentID == nil }.map(\.id), expected)
            XCTAssertEqual(components.first { $0.id == "a" }?.childIDs, ["c", "e", "f"])
            XCTAssertEqual(components.first { $0.id == "b" }?.partID, "p")
            XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
            XCTAssertEqual(
                try changed.editorContents().nodes.map(\.value), try original.editorContents().nodes.map(\.value))
            XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).components(), components)
            let xml = try XMLDocument(data: changed.modelXML)
            let container = try XCTUnwrap(xml.rootElement()?.elements(forName: "components").first)
            XCTAssertEqual(container.children?.map(\.name), ["component", nil, "future", "component", "component"])
            XCTAssertEqual(
                container.elements(forName: "future").first?.attribute(forName: "value")?.stringValue, "root")
            XCTAssertEqual(
                (try xml.nodes(forXPath: "//component[@id='a']").first as? XMLElement)?.attribute(forName: "future")?
                    .stringValue, "group")
            XCTAssertNotNil(try xml.nodes(forXPath: "//component[@id='a']/future").first)
            XCTAssertEqual(try changed.editorContents().parts.first?.isLocked, true)
        }
        for (direction, expected) in [
            (ComponentOrderMove.up, ["e", "c", "f"]), (.down, ["c", "f", "e"]), (.first, ["e", "c", "f"]),
            (.last, ["c", "f", "e"]),
        ] {
            let changed = try original.applying(.reorderComponent(id: "e", direction: direction))
            XCTAssertEqual(try changed.components().first { $0.id == "a" }?.childIDs, expected)
            XCTAssertEqual(try changed.components().filter { $0.parentID == nil }.map(\.id), ["a", "b", "d"])
        }
    }
    func testBoundaryMovesAreExactNoOpsAndHistoryPreservesRedo() throws {
        let original = try document()
        for (id, direction) in [
            ("a", ComponentOrderMove.up), ("a", .first), ("d", .down), ("d", .last), ("c", .up), ("c", .first),
            ("f", .down), ("f", .last),
        ] {
            XCTAssertEqual(
                try original.applying(.reorderComponent(id: id, direction: direction)).encoded(), original.encoded())
        }
        var history = DocumentHistory(document: original)
        try history.apply(.reorderComponent(id: "b", direction: .up))
        let edited = history.document.encoded()
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        try history.apply(.reorderComponent(id: "a", direction: .up))
        XCTAssertTrue(history.canRedo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), edited)
        try history.beginTransaction()
        try history.apply(.reorderComponent(id: "b", direction: .down))
        try history.apply(.reorderComponent(id: "b", direction: .up))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), edited)
    }
    func testMissingAmbiguousAndUnsupportedTargetsRejectAndUnrelatedGraphIsPreserved() throws {
        let original = try document(nodes: "<node id='unsupported' future='keep'/>")
        XCTAssertNoThrow(try original.applying(.reorderComponent(id: "b", direction: .up)))
        XCTAssertThrowsError(try original.applying(.reorderComponent(id: "missing", direction: .down))) {
            XCTAssertEqual($0 as? DocumentError, .missingComponent("missing"))
        }
        for xml in ["<component id='same'/><component id='same'/>", "<future id='unsupported'/>"] {
            let invalid = try document(xml)
            XCTAssertThrowsError(try invalid.applying(.reorderComponent(id: "same", direction: .up)))
            XCTAssertEqual(invalid.encoded(), try document(xml).encoded())
        }
        let only = try document("<component id='only'/>")
        for direction in ComponentOrderMove.allCases {
            XCTAssertEqual(
                try only.applying(.reorderComponent(id: "only", direction: direction)).encoded(), only.encoded())
        }
    }
    func testOrderDestinationRejectsInvalidIndicesAndReturnsNoTargetAtBoundaries() {
        for move in ComponentOrderMove.allCases {
            XCTAssertNil(move.destinationIndex(from: -1, count: 3))
            XCTAssertNil(move.destinationIndex(from: 3, count: 3))
            XCTAssertNil(move.destinationIndex(from: 0, count: 0))
            XCTAssertNil(move.destinationIndex(from: 0, count: -1))
            XCTAssertNil(move.destinationIndex(from: Int.max, count: 3))
            XCTAssertNil(move.destinationIndex(from: 0, count: 1))
        }
        XCTAssertNil(ComponentOrderMove.down.destinationIndex(from: Int.max - 1, count: Int.max))
        XCTAssertEqual(ComponentOrderMove.last.destinationIndex(from: 0, count: Int.max), Int.max - 1)
        XCTAssertEqual(ComponentOrderMove.first.destinationIndex(from: 2, count: 4), 0)
        XCTAssertEqual(ComponentOrderMove.last.destinationIndex(from: 1, count: 4), 3)
    }
}
