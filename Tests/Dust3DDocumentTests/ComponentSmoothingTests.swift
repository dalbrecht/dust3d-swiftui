import Dust3DDocument
import Foundation
import XCTest

final class ComponentSmoothingTests: XCTestCase {
    private func document(_ attributes: String = "", components: String? = nil) throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='root'><components>\(components ?? "<component id='a' future='kept' \(attributes)><component id='b'/><!--keep--></component>")</components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testCutoffReadPreservesDefaultsSupportedSpellingsAndUnsupportedValues() throws {
        for (attributes, expected): (String, Double?) in [
            ("", 0), ("smoothCutoffDegrees=''", 0), ("smoothCutoffDegrees='-0'", 0),
            ("smoothCutoffDegrees='090.00'", 90), ("smoothCutoffDegrees='180'", 180),
            ("smoothCutoffDegrees='181'", nil), ("smoothCutoffDegrees='-1'", nil),
            ("smoothCutoffDegrees='nan'", nil), ("smoothCutoffDegrees='inf'", nil),
            ("smoothCutoffDegrees='future'", nil),
        ] {
            let original = try document(attributes)
            let bytes = original.encoded()
            XCTAssertEqual(try original.components().first?.smoothCutoffDegrees, expected, attributes)
            XCTAssertEqual(original.encoded(), bytes)
        }
    }

    func testChangingAndResettingCutoffPreservesOtherXmlAssetsAndExactHistory() throws {
        let original = try document("smoothCutoffDegrees='future'")
        var history = DocumentHistory(document: original)
        try history.apply(.setComponentSmoothCutoffDegrees(id: "a", degrees: 90))
        let changed = history.document
        XCTAssertEqual(try changed.components().first?.smoothCutoffDegrees, 90)
        XCTAssertEqual(try changed.components().first?.childIDs, ["b"])
        XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        XCTAssertTrue(String(decoding: changed.modelXML, as: UTF8.self).contains("<!--keep-->"))
        let xml = try XMLDocument(data: changed.modelXML)
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//component[@id='a']").first as? XMLElement)?.attribute(forName: "future")?
                .stringValue, "kept")
        XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).components(), try changed.components())
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed.encoded())
        let reset = try changed.applying(.setComponentSmoothCutoffDegrees(id: "a", degrees: 0))
        XCTAssertEqual(try reset.components().first?.smoothCutoffDegrees, 0)
        XCTAssertFalse(String(decoding: reset.modelXML, as: UTF8.self).contains("smoothCutoffDegrees="))
        XCTAssertEqual(
            try original.applying(.setComponentSmoothCutoffDegrees(id: "a", degrees: 180)).components().first?
                .smoothCutoffDegrees, 180)
    }

    func testInvalidCutoffMissingAndAmbiguousIdentitiesRejectWithoutChangingDocument() throws {
        let original = try document()
        for value: Double in [-0.01, 180.01, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try original.applying(.setComponentSmoothCutoffDegrees(id: "a", degrees: value))) {
                XCTAssertEqual($0 as? DocumentError, .invalidComponentSmoothing)
            }
        }
        XCTAssertThrowsError(try original.applying(.setComponentSmoothCutoffDegrees(id: "missing", degrees: 90))) {
            XCTAssertEqual($0 as? DocumentError, .missingComponent("missing"))
        }
        let ambiguous = try document(components: "<component id='a'/><component id='a'/>")
        XCTAssertThrowsError(try ambiguous.applying(.setComponentSmoothCutoffDegrees(id: "a", degrees: 90))) {
            XCTAssertEqual($0 as? DocumentError, .invalidComponent)
        }
        XCTAssertEqual(try original.components().first?.smoothCutoffDegrees, 0)
    }

    func testSemanticNoOpPreservesNumericSpellingAndRedo() throws {
        let original = try document("smoothCutoffDegrees='090.00'")
        var history = DocumentHistory(document: original)
        try history.apply(.setComponentSmoothCutoffDegrees(id: "a", degrees: 180))
        let changed = history.document.encoded()
        XCTAssertTrue(history.undo())
        try history.apply(.setComponentSmoothCutoffDegrees(id: "a", degrees: 90))
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed)
        let absent = try document()
        XCTAssertEqual(
            try absent.applying(.setComponentSmoothCutoffDegrees(id: "a", degrees: -0.0)).encoded(), absent.encoded())
    }
}
