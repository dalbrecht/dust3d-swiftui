import Dust3DDocument
import Foundation
import XCTest

final class PartModifierTests: XCTestCase {
    private func document(_ attributes: String = "", parts: String? = nil) throws -> Dust3DDocument {
        let part = parts ?? "<part id='p' future='retained' \(attributes)/>"
        let model = Data(
            "<canvas><nodes><node id='n' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts>\(part)</parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testModifierDefaultsKnownSpellingsAndUnknownValuesRemainLossless() throws {
        let original = try document()
        for property in PartModifierProperty.allCases {
            XCTAssertEqual(
                try original.editorContents().parts.first?.modifierValue(property), property == .interpolation)
            for text in ["true", "True", "1", "false", "False", "0", "future", "TRUE", ""] {
                let source = try document("\(property.rawValue)='\(text)'")
                let bytes = source.encoded()
                let expected: Bool?
                if ["true", "True", "1"].contains(text) {
                    expected = true
                } else if ["false", "False", "0"].contains(text) || (text.isEmpty && property != .interpolation) {
                    expected = false
                } else {
                    expected = nil
                }
                XCTAssertEqual(
                    try source.editorContents().parts.first?.modifierValue(property), expected, "\(property): \(text)")
                XCTAssertEqual(source.encoded(), bytes)
            }
        }
    }

    func testEveryModifierEditAndHistoryPreserveOtherFlagsUnknownDataAssetsAndNodes() throws {
        for property in PartModifierProperty.allCases {
            let original = try document("\(property.rawValue)='future' locked='true' visible='false' disabled='true'")
            for enabled in [false, true] {
                var history = DocumentHistory(document: original)
                try history.apply(.setPartModifier(id: "p", property: property, value: enabled))
                let changed = history.document
                let part = try XCTUnwrap(changed.editorContents().parts.first)
                XCTAssertEqual(part.modifierValue(property), enabled)
                for other in PartModifierProperty.allCases where other != property {
                    XCTAssertEqual(part.modifierValue(other), other.defaultValue)
                }
                XCTAssertTrue(part.isLocked)
                XCTAssertTrue(part.isDisabled)
                XCTAssertFalse(part.isVisible)
                XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
                XCTAssertEqual(
                    try changed.editorContents().nodes.map(\.value), try original.editorContents().nodes.map(\.value))
                let xml = try XMLDocument(data: changed.modelXML)
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "//part").first as? XMLElement)?.attribute(forName: "future")?.stringValue,
                    "retained")
                XCTAssertEqual(
                    try Dust3DDocument(data: changed.encoded()).editorContents().parts,
                    try changed.editorContents().parts)
                XCTAssertTrue(history.undo())
                XCTAssertEqual(history.document.encoded(), original.encoded())
                XCTAssertTrue(history.redo())
                XCTAssertEqual(history.document.encoded(), changed.encoded())
            }
        }
    }

    func testModifierNoOpsKeepOriginalSpellingsAndRedo() throws {
        for property in PartModifierProperty.allCases {
            let original = try document("\(property.rawValue)='True'")
            var history = DocumentHistory(document: original)
            try history.apply(.setPartModifier(id: "p", property: property, value: false))
            let changed = history.document.encoded()
            XCTAssertTrue(history.undo())
            try history.apply(.setPartModifier(id: "p", property: property, value: true))
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed)
        }
    }

    func testMissingAndAmbiguousPartIdentitiesRejectAtomically() throws {
        let original = try document()
        XCTAssertThrowsError(
            try original.applying(.setPartModifier(id: "missing", property: .subdivision, value: true))
        ) {
            XCTAssertEqual($0 as? DocumentError, .missingPart("missing"))
        }
        let ambiguous = try document(parts: "<part id='p'/><part id='p'/>")
        XCTAssertThrowsError(try ambiguous.applying(.setPartModifier(id: "p", property: .subdivision, value: true))) {
            XCTAssertEqual($0 as? DocumentError, .invalidNode)
        }
    }
}
