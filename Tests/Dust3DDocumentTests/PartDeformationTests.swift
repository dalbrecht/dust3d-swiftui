import Dust3DDocument
import Foundation
import XCTest

final class PartDeformationTests: XCTestCase {
    private func document(_ attributes: String = "", parts: String? = nil) throws -> Dust3DDocument {
        let part = parts ?? "<part id='p' future='keep' locked='true' visible='false' disabled='true' \(attributes)/>"
        let model = Data(
            "<canvas><nodes><node id='n' partId='p' x='.5' y='.5' z='.5' radius='.1' deformWidth='1.25'/></nodes><edges/><parts>\(part)</parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testDefaultsSupportedScalesAndAmbiguousMetadataRemainLossless() throws {
        let baseline = try document()
        let part = try XCTUnwrap(baseline.editorContents().parts.first)
        XCTAssertEqual(part.isDeformationUnified, false)
        for property in PartDeformationProperty.allCases {
            XCTAssertEqual(part.deformationScale(property), 1)
            for text in ["0", "2", "0.995", "1.005", "1e0", "future", "", "nan", "inf", "-0.1", "2.1"] {
                let source = try document("\(property.rawValue)='\(text)'")
                let originalBytes = source.encoded()
                let value = try source.editorContents().parts.first?.deformationScale(property)
                if let number = Double(text), number.isFinite && (0...2).contains(number) {
                    XCTAssertEqual(value, number)
                } else {
                    XCTAssertNil(value, text)
                }
                XCTAssertEqual(source.encoded(), originalBytes)
            }
        }
        for text in ["true", "True", "1", "false", "False", "0", "", "future"] {
            let source = try document("deformUnified='\(text)'")
            let expected: Bool? =
                ["true", "True", "1"].contains(text)
                ? true : (["false", "False", "0", ""].contains(text) ? false : nil)
            XCTAssertEqual(try source.editorContents().parts.first?.isDeformationUnified, expected)
        }
    }

    func testBoundaryAndNearDefaultEditsPreserveGraphAssetsAndExactHistory() throws {
        for property in PartDeformationProperty.allCases {
            for value in [0.0, 0.995, 1.0, 1.005, 2.0] {
                let source = try document("\(property.rawValue)='future' deformUnified='future'")
                var history = DocumentHistory(document: source)
                try history.apply(.setPartDeformationScale(id: "p", property: property, value: value))
                let changed = history.document
                let part = try XCTUnwrap(changed.editorContents().parts.first)
                XCTAssertEqual(part.deformationScale(property), value)
                XCTAssertNil(part.isDeformationUnified)
                XCTAssertTrue(part.isLocked)
                XCTAssertTrue(part.isDisabled)
                XCTAssertFalse(part.isVisible)
                XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
                XCTAssertEqual(try changed.editorContents().nodes, try source.editorContents().nodes)
                let xml = try XMLDocument(data: changed.modelXML)
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "//part").first as? XMLElement)?.attribute(forName: "future")?.stringValue,
                    "keep")
                XCTAssertEqual(
                    try Dust3DDocument(data: changed.encoded()).editorContents().parts,
                    try changed.editorContents().parts)
                let attribute = (try xml.nodes(forXPath: "//part").first as? XMLElement)?.attribute(
                    forName: property.rawValue)
                XCTAssertEqual(attribute == nil, value == 1)
                XCTAssertTrue(history.undo())
                XCTAssertEqual(history.document.encoded(), source.encoded())
                XCTAssertTrue(history.redo())
                XCTAssertEqual(history.document.encoded(), changed.encoded())
            }
        }
    }

    func testUnifiedEditsPreserveUnsupportedScalesAndExactHistory() throws {
        for value in [false, true] {
            let source = try document("deformWidth='future' deformThickness='1.005' deformUnified='future'")
            var history = DocumentHistory(document: source)
            try history.apply(.setPartDeformationUnified(id: "p", value: value))
            let changed = history.document
            let part = try XCTUnwrap(changed.editorContents().parts.first)
            XCTAssertEqual(part.isDeformationUnified, value)
            XCTAssertNil(part.deformationScale(.width))
            XCTAssertEqual(part.deformationScale(.thickness), 1.005)
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
    }

    func testNoOpScaleAndUnifiedCommandsRetainSpellingsBytesAndRedo() throws {
        let source = try document("deformWidth='1e0' deformUnified='True'")
        var history = DocumentHistory(document: source)
        try history.apply(.setPartDeformationScale(id: "p", property: .width, value: 0.995))
        let changed = history.document.encoded()
        XCTAssertTrue(history.undo())
        try history.apply(.setPartDeformationScale(id: "p", property: .width, value: 1))
        try history.apply(.setPartDeformationUnified(id: "p", value: true))
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed)
    }

    func testInvalidScalesMissingPartsAndAmbiguousIdentitiesRejectAtomically() throws {
        let source = try document()
        for value in [-0.001, 2.001, Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try source.applying(.setPartDeformationScale(id: "p", property: .width, value: value)))
            {
                XCTAssertEqual($0 as? DocumentError, .invalidPartDeformation)
            }
        }
        for command in [
            DocumentCommand.setPartDeformationScale(id: "missing", property: .width, value: 1.5),
            .setPartDeformationUnified(id: "missing", value: true),
        ] {
            XCTAssertThrowsError(try source.applying(command)) {
                XCTAssertEqual($0 as? DocumentError, .missingPart("missing"))
            }
        }
        let duplicate = try document(parts: "<part id='p'/><part id='p'/>")
        XCTAssertThrowsError(try duplicate.applying(.setPartDeformationUnified(id: "p", value: true))) {
            XCTAssertEqual($0 as? DocumentError, .invalidNode)
        }
    }
}
