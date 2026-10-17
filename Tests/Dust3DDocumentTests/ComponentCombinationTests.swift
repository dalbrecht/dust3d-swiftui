import Dust3DDocument
import Foundation
import XCTest

final class ComponentCombinationTests: XCTestCase {
    private func document(_ components: String) throws -> Dust3DDocument {
        let model = Data("<canvas future='root'><components>\(components)</components></canvas>".utf8)
        let header =
            "<ds3 future='archive'><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testModesDecodeDefaultsLegacyInversionAndUnknownValuesWithoutChangingBytes() throws {
        for (attributes, expected): (String, ComponentCombineMode?) in [
            ("", .normal), ("combineMode='Normal'", .normal),
            ("combineMode='Inversion'", .inversion), ("combineMode='Uncombined'", .uncombined),
            ("inverse='true'", .inversion), ("inverse='True'", .inversion), ("inverse='1'", .inversion),
            ("combineMode='Normal' inverse='true'", .inversion),
            ("combineMode='Uncombined' inverse='true'", .uncombined),
            ("inverse='false'", .normal), ("inverse='TRUE'", .normal),
            ("combineMode='Future' inverse='true'", nil), ("combineMode=''", .normal),
        ] {
            let original = try document("<component id='a' \(attributes)/>")
            let bytes = original.encoded()
            XCTAssertEqual(try original.components().first?.combineMode, expected, attributes)
            XCTAssertEqual(original.encoded(), bytes)
        }
    }

    func testExplicitModeEditsRetainHierarchyOpaqueDataAssetsAndRoundTrip() throws {
        let original = try document(
            "<component id='a' combineMode='Future' inverse='true' future='retained'><component id='b' linkDataType='future' linkData='opaque'/><!--keep--><future/></component>"
        )
        for mode in ComponentCombineMode.allCases {
            let changed = try original.applying(.setComponentCombineMode(id: "a", mode: mode))
            XCTAssertEqual(try changed.components().first?.combineMode, mode)
            XCTAssertEqual(try changed.components().first?.childIDs, ["b"])
            XCTAssertEqual(try changed.components().last?.linkData, "opaque")
            let xml = try XMLDocument(data: changed.modelXML)
            let component = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='a']").first as? XMLElement)
            XCTAssertEqual(component.attribute(forName: "combineMode")?.stringValue, mode.rawValue)
            XCTAssertNil(component.attribute(forName: "inverse"))
            XCTAssertEqual(component.attribute(forName: "future")?.stringValue, "retained")
            XCTAssertTrue(changed.modelXML.range(of: Data("<!--keep-->".utf8)) != nil)
            XCTAssertNotNil(try xml.nodes(forXPath: "//component[@id='a']/future").first)
            XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
            XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).components(), try changed.components())
        }
    }

    func testNormalClearsLegacyInversionWhileSemanticNoOpsRetainSourceSpellings() throws {
        let original = try document("<component id='a' combineMode='Normal' inverse='True'/><component id='b'/>")
        XCTAssertEqual(
            try original.applying(.setComponentCombineMode(id: "a", mode: .inversion)).encoded(), original.encoded())
        XCTAssertEqual(
            try original.applying(.setComponentCombineMode(id: "b", mode: .normal)).encoded(), original.encoded())
        let normal = try original.applying(.setComponentCombineMode(id: "a", mode: .normal))
        XCTAssertEqual(try normal.components().first?.combineMode, .normal)
        XCTAssertFalse(String(decoding: normal.modelXML, as: UTF8.self).contains("inverse="))
    }

    func testHistoryRestoresExactArchivesAndNoOpAfterUndoKeepsRedo() throws {
        let original = try document("<component id='a' inverse='1' future='kept'/>")
        var history = DocumentHistory(document: original)
        try history.apply(.setComponentCombineMode(id: "a", mode: .uncombined))
        let changed = history.document.encoded()
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        try history.apply(.setComponentCombineMode(id: "a", mode: .inversion))
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed)
    }

    func testMissingOrAmbiguousComponentsRejectAtomically() throws {
        let original = try document("<component id='a'/>")
        XCTAssertThrowsError(try original.applying(.setComponentCombineMode(id: "missing", mode: .normal))) {
            XCTAssertEqual($0 as? DocumentError, .missingComponent("missing"))
        }
        let ambiguous = try document("<component id='a'/><component id='a'/>")
        XCTAssertThrowsError(try ambiguous.applying(.setComponentCombineMode(id: "a", mode: .normal))) {
            XCTAssertEqual($0 as? DocumentError, .invalidComponent)
        }
        XCTAssertEqual(try original.components().first?.combineMode, .normal)
    }
}
