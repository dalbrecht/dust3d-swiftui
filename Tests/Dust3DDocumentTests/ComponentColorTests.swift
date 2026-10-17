import Dust3DDocument
import Foundation
import XCTest

final class ComponentColorTests: XCTestCase {
    private func document(_ color: String? = nil) throws -> Dust3DDocument {
        let attribute = color.map { "color='\($0)'" } ?? ""
        let model = Data(
            "<canvas><nodes/><edges/><parts><part id='p' future='part'/></parts><components><component id='g' future='group' \(attribute)><component id='c' linkDataType='partId' linkData='p' color='#123456' future='child'/></component></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testColorParsingPreservesAlphaFirstOrderAndStrictEightBitValues() throws {
        let rgb = try XCTUnwrap(DocumentColor(archiveValue: "#aB01fF"))
        XCTAssertEqual(rgb.red, 171)
        XCTAssertEqual(rgb.green, 1)
        XCTAssertEqual(rgb.blue, 255)
        XCTAssertEqual(rgb.alpha, 255)
        XCTAssertEqual(rgb.archiveValue, "#AB01FF")
        let rgba = try XCTUnwrap(DocumentColor(archiveValue: "#80102030"))
        XCTAssertEqual(rgba, DocumentColor(red: 16, green: 32, blue: 48, alpha: 128))
        XCTAssertEqual(rgba.archiveValue, "#80102030")
        XCTAssertEqual(DocumentColor(red: 0, green: 0, blue: 0, alpha: 0).archiveValue, "#00000000")
        XCTAssertEqual(DocumentColor(archiveValue: "#FF102030")?.archiveValue, "#102030")
        for text in [
            "", "red", "#abc", "#12345", "#1234567", "#123456789", "#GG0000", "#0+0000", "#+00000", "#-00000",
            "#ＦＦ0000", " #123456",
            "#123456\n", "1234567",
        ] {
            XCTAssertNil(DocumentColor(archiveValue: text), text)
        }
    }

    func testInterpretingAbsentKnownAndUnsupportedColorDoesNotRewriteArchive() throws {
        XCTAssertEqual(try document().components().first?.color, .unset)
        for text in ["#ab01FF", "#FFab01ff", "#80102030", "future", "red", "", "#00xx00"] {
            let source = try document(text)
            let color = try XCTUnwrap(source.components().first?.color)
            if let parsed = DocumentColor(archiveValue: text) {
                XCTAssertEqual(color, .value(parsed))
            } else {
                XCTAssertEqual(color, .unsupported(text))
            }
            XCTAssertEqual(source.encoded(), try document(text).encoded())
        }
    }

    func testColorEditsAndRemovalPreserveHierarchyAssetsAndExactUndoRedoAndReopen() throws {
        let source = try document("future")
        var history = DocumentHistory(document: source)
        let color = DocumentColor(red: 17, green: 34, blue: 51, alpha: 68)
        try history.apply(.setComponentColor(id: "g", color: color))
        let changed = history.document
        XCTAssertEqual(try changed.components().first?.color, .value(color))
        XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
        let xml = try XMLDocument(data: changed.modelXML)
        let group = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='g']").first as? XMLElement)
        XCTAssertEqual(group.attribute(forName: "future")?.stringValue, "group")
        XCTAssertEqual(group.attribute(forName: "color")?.stringValue, "#44112233")
        let child = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='c']").first as? XMLElement)
        XCTAssertEqual(child.attribute(forName: "future")?.stringValue, "child")
        XCTAssertEqual(child.attribute(forName: "color")?.stringValue, "#123456")
        XCTAssertEqual(
            try Dust3DDocument(data: changed.encoded()).components(),
            try changed.components())
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed.encoded())
        try history.apply(.setComponentColor(id: "g", color: nil))
        XCTAssertEqual(try history.document.components().first?.color, .unset)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), changed.encoded())
    }

    func testSemanticNoOpsKeepOriginalSpellingAndRedoAndMissingComponentRejectsAtomically() throws {
        for text: String? in [nil, "#ffAB01FF", "#ab01ff"] {
            let source = try document(text)
            var history = DocumentHistory(document: source)
            try history.apply(.setComponentColor(id: "g", color: DocumentColor(red: 0, green: 1, blue: 2)))
            XCTAssertTrue(history.undo())
            try history.apply(.setComponentColor(id: "g", color: text.flatMap(DocumentColor.init(archiveValue:))))
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
            XCTAssertThrowsError(try history.apply(.setComponentColor(id: "missing", color: nil))) {
                XCTAssertEqual($0 as? DocumentError, .missingComponent("missing"))
            }
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
        }
    }
}
