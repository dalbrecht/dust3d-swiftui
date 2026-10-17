import Dust3DDocument
import Foundation
import XCTest

final class PartMaterialTests: XCTestCase {
    private func document(_ attributes: String = "") throws -> Dust3DDocument {
        let model = Data(
            "<canvas><nodes/><edges/><parts><part id='p' future='keep' locked='true' \(attributes)/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testSupportedDefaultsLegacyDecimalsAndUnsupportedValuesRemainLossless() throws {
        for property in PartMaterialProperty.allCases {
            let baseline = try document()
            XCTAssertEqual(try baseline.editorContents().parts.first?.materialValue(property), property.defaultValue)
            for text in ["0", "1", "0,25", "1e-1", "future", "", "nan", "inf", "-0.1", "2.1", "1e-9999", "1e-50"] {
                let source = try document("\(property.rawValue)='\(text)'")
                let bytes = source.encoded()
                let value = try source.editorContents().parts.first?.materialValue(property)
                if let expected = Double(text.replacingOccurrences(of: ",", with: ".")), expected.isFinite,
                    property.bounds.contains(expected), !["1e-9999", "1e-50"].contains(text)
                {
                    XCTAssertEqual(value, expected)
                } else {
                    XCTAssertNil(value, text)
                }
                XCTAssertEqual(source.encoded(), bytes)
            }
        }
        XCTAssertEqual(try document("emissive='2'").editorContents().parts.first?.materialValue(.emissive), 2)
        XCTAssertNil(try document("metallic='2'").editorContents().parts.first?.materialValue(.metallic))
        XCTAssertNil(try document("roughness='2'").editorContents().parts.first?.materialValue(.roughness))
    }

    func testMaterialEditsPreserveUnrelatedDataAndExactUndoRedoAndReopen() throws {
        for property in PartMaterialProperty.allCases {
            for value in [0, 0.005, 0.5, 1, property.bounds.upperBound] {
                let source = try document("\(property.rawValue)='future' color='opaque' metalness='legacy-unknown'")
                var history = DocumentHistory(document: source)
                try history.apply(.setPartMaterial(id: "p", property: property, value: value))
                let changed = history.document
                XCTAssertEqual(try changed.editorContents().parts.first?.materialValue(property), value)
                XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
                let xml = try XMLDocument(data: changed.modelXML)
                let part = try XCTUnwrap(try xml.nodes(forXPath: "//part").first as? XMLElement)
                XCTAssertEqual(part.attribute(forName: "future")?.stringValue, "keep")
                XCTAssertEqual(part.attribute(forName: "metalness")?.stringValue, "legacy-unknown")
                XCTAssertEqual(part.attribute(forName: "color")?.stringValue, "opaque")
                XCTAssertEqual(part.attribute(forName: "locked")?.stringValue, "true")
                XCTAssertEqual(part.attribute(forName: property.rawValue) == nil, value == property.defaultValue)
                XCTAssertEqual(
                    try Dust3DDocument(data: changed.encoded()).editorContents().parts,
                    try changed.editorContents().parts)
                XCTAssertTrue(history.undo())
                XCTAssertEqual(history.document.encoded(), source.encoded())
                XCTAssertTrue(history.redo())
                XCTAssertEqual(history.document.encoded(), changed.encoded())
            }
        }
    }

    func testChangingRolesPreservesKnownAndUnsupportedMaterialMetadata() throws {
        let source = try document("metallic='0,5' roughness='future' emissive='2'")
        for target in PartTarget.allCases {
            let changed = try source.applying(.setPartTarget(id: "p", target: target))
            let part = try XCTUnwrap(changed.editorContents().parts.first)
            XCTAssertEqual(part.materialValue(.metallic), 0.5)
            XCTAssertNil(part.materialValue(.roughness))
            XCTAssertEqual(part.materialValue(.emissive), 2)
            let xml = try XMLDocument(data: changed.modelXML)
            let element = try XCTUnwrap(try xml.nodes(forXPath: "//part").first as? XMLElement)
            XCTAssertEqual(element.attribute(forName: "roughness")?.stringValue, "future")
            XCTAssertEqual(element.attribute(forName: "metallic")?.stringValue, "0,5")
        }
    }

    func testNoOpPreservesOriginalSpellingAndRedoAndInvalidEditsLeaveHistoryUnchanged() throws {
        for property in PartMaterialProperty.allCases {
            let source = try document("\(property.rawValue)='0,50'")
            var history = DocumentHistory(document: source)
            try history.apply(.setPartMaterial(id: "p", property: property, value: 0.75))
            XCTAssertTrue(history.undo())
            try history.apply(.setPartMaterial(id: "p", property: property, value: 0.5))
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
            for invalid in [
                -0.1, property.bounds.upperBound + 0.01, .nan, .infinity, 1e-50, Double.leastNonzeroMagnitude,
            ] {
                XCTAssertThrowsError(try history.apply(.setPartMaterial(id: "p", property: property, value: invalid))) {
                    XCTAssertEqual($0 as? DocumentError, .invalidPartMaterial)
                }
                XCTAssertEqual(history.document.encoded(), source.encoded())
                XCTAssertTrue(history.canRedo)
            }
            XCTAssertThrowsError(try history.apply(.setPartMaterial(id: "missing", property: property, value: 0.5))) {
                XCTAssertEqual($0 as? DocumentError, .missingPart("missing"))
            }
        }
    }
}
