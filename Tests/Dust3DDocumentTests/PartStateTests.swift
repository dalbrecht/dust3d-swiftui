import Dust3DDocument
import Foundation
import XCTest

final class PartStateTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='root'><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1' future='node'/></nodes><parts><part id='p' name='Body' visible='True' locked='0' disabled='false' future='part'><future/></part><part id='empty'/></parts><components><component id='c' linkData='p' linkDataType='partId' name='Component name' future='component'/></components></canvas>"
                .utf8)
        let header =
            "<ds3 future='archive'><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4' future='asset'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
    func testPartsRetainDocumentOrderNamesAndDefaults() throws {
        let original = try document()
        let contents = try original.editorContents()
        XCTAssertEqual(contents.parts.map(\.id), ["p", "empty"])
        XCTAssertEqual(contents.parts.map(\.title), ["Body", "Part 2"])
        XCTAssertTrue(contents.parts.allSatisfy(\.isVisible))
        XCTAssertTrue(contents.parts.allSatisfy(\.isEditable))
        XCTAssertFalse(contents.parts[0].isLocked)
        XCTAssertFalse(contents.parts[0].isDisabled)
        for (property, value) in [(PartStateProperty.visible, true), (.locked, false), (.disabled, false)] {
            XCTAssertEqual(
                try original.applying(.setPartState(id: "p", property: property, value: value)).encoded(),
                original.encoded())
        }
        XCTAssertEqual(try original.applying(.setPartName(id: "p", name: "Body")).encoded(), original.encoded())
    }
    func testVisibilityLockAndDisableAffectGraphEditingAndAreReversible() throws {
        let original = try document()
        for property in PartStateProperty.allCases {
            let value = property != .visible
            let changed = try original.applying(.setPartState(id: "p", property: property, value: value))
            let contents = try changed.editorContents()
            XCTAssertFalse(contents.nodes[0].isEditable)
            XCTAssertEqual(contents.nodes[0].isVisible, property == .locked)
            XCTAssertThrowsError(try changed.applying(.removeNode(id: "a")))
            XCTAssertThrowsError(
                try changed.applying(
                    .addNode(id: "new", partID: "p", componentID: nil, position: .init(x: 1, y: 0, z: 0), radius: 0.1)))
            let restored = try changed.applying(.setPartState(id: "p", property: property, value: !value))
            XCTAssertTrue(try restored.editorContents().nodes[0].isEditable)
            var history = DocumentHistory(document: original)
            try history.beginTransaction()
            try history.apply(.setPartState(id: "p", property: property, value: value))
            try history.endTransaction()
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
    }
    func testNamingPreservesUnknownPartComponentAndAssetData() throws {
        let original = try document()
        let name = "  Body & <head> 🦊  "
        let changed = try original.applying(.setPartName(id: "p", name: name))
        let part = try XCTUnwrap(changed.editorContents().parts.first)
        XCTAssertEqual(part.name, "Body & <head> 🦊")
        XCTAssertEqual(changed.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
        let xml = try XMLDocument(data: changed.modelXML)
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//part[@id='p']").first as? XMLElement)?.attribute(forName: "future")?
                .stringValue, "part")
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//component").first as? XMLElement)?.attribute(forName: "name")?.stringValue,
            "Component name")
        XCTAssertNotNil(try xml.nodes(forXPath: "//part[@id='p']/future").first)
        let cleared = try changed.applying(.setPartName(id: "p", name: " "))
        XCTAssertEqual(try cleared.editorContents().parts.first?.title, "Part 1")
        XCTAssertEqual(try cleared.applying(.setPartName(id: "p", name: "")).encoded(), cleared.encoded())
    }
    func testPartNameBoundsInvalidInputsAndMissingPartsAreAtomic() throws {
        let original = try document()
        XCTAssertNoThrow(try original.applying(.setPartName(id: "p", name: String(repeating: "é", count: 512))))
        for name in [String(repeating: "é", count: 513), "bad\0name", "bad\nname", "bad\u{2028}name", "bad\u{FFFF}"] {
            XCTAssertThrowsError(try original.applying(.setPartName(id: "p", name: name))) {
                XCTAssertEqual($0 as? DocumentError, .invalidPartName)
            }
        }
        XCTAssertThrowsError(try original.applying(.setPartName(id: "missing", name: "Name"))) {
            XCTAssertEqual($0 as? DocumentError, .missingPart("missing"))
        }
        XCTAssertThrowsError(try original.applying(.setPartState(id: "missing", property: .locked, value: true)))
        XCTAssertEqual(original.encoded(), try document().encoded())
    }
    func testPartStateNetZeroTransactionsRestoreOriginalSpellingsAndRedo() throws {
        let original = try document()
        var history = DocumentHistory(document: original)
        try history.apply(.setPartName(id: "p", name: "Changed"))
        XCTAssertTrue(history.undo())
        try history.beginTransaction()
        try history.apply(.setPartState(id: "p", property: .locked, value: true))
        try history.apply(.setPartState(id: "p", property: .locked, value: false))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)
    }
}
