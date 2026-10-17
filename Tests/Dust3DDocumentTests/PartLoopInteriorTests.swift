import Dust3DDocument
import Foundation
import XCTest

final class PartLoopInteriorTests: XCTestCase {
    private func document(_ text: String? = nil) throws -> Dust3DDocument {
        let attribute = text.map { "fillLoopInterior='\($0)'" } ?? ""
        let model = Data(
            "<canvas><nodes><node id='n' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p' target='StitchingLoop' locked='true' visible='false' disabled='true' future='keep' \(attribute)/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
    func testKnownDefaultAndUnsupportedFlagsRemainLosslessOnRead() throws {
        for text in [nil, "", "true", "True", "1", "false", "False", "0", "future", "TRUE"] as [String?] {
            let source = try document(text)
            let expected: Bool? =
                ["true", "True", "1"].contains(text ?? "")
                ? true
                : ["", "false", "False", "0"].contains(text ?? "") ? false : nil
            XCTAssertEqual(try source.editorContents().parts.first?.isLoopInteriorFilled, expected)
            XCTAssertEqual(try Dust3DDocument(data: source.encoded()).encoded(), source.encoded())
        }
    }
    func testExplicitReplacementPreservesGraphFlagsOpaqueAssetsAndExactHistory() throws {
        for value in [false, true] {
            let source = try document("future")
            var history = DocumentHistory(document: source)
            try history.apply(.setPartFillLoopInterior(id: "p", value: value))
            let changed = history.document
            let part = try XCTUnwrap(changed.editorContents().parts.first)
            XCTAssertEqual(part.isLoopInteriorFilled, value)
            XCTAssertEqual(part.target, .stitchingLoop)
            XCTAssertTrue(part.isLocked)
            XCTAssertTrue(part.isDisabled)
            XCTAssertFalse(part.isVisible)
            XCTAssertEqual(try changed.editorContents().nodes, try source.editorContents().nodes)
            XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            let xml = try XMLDocument(data: changed.modelXML)
            let element = try XCTUnwrap(try xml.nodes(forXPath: "//part").first as? XMLElement)
            XCTAssertEqual(element.attribute(forName: "future")?.stringValue, "keep")
            XCTAssertEqual(element.attribute(forName: "fillLoopInterior")?.stringValue, value ? "true" : nil)
            XCTAssertEqual(
                try Dust3DDocument(data: changed.encoded()).editorContents().parts, try changed.editorContents().parts)
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
    }
    func testSemanticNoOpsPreserveSourceSpellingAndRedoAndMissingOwnersReject() throws {
        for text in [nil, "", "true", "True", "1", "false", "False", "0"] as [String?] {
            let source = try document(text)
            let value = try XCTUnwrap(source.editorContents().parts.first?.isLoopInteriorFilled)
            var history = DocumentHistory(document: source)
            try history.apply(.setPartName(id: "p", name: "Temporary"))
            XCTAssertTrue(history.undo())
            try history.apply(.setPartFillLoopInterior(id: "p", value: value))
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
            XCTAssertThrowsError(try history.apply(.setPartFillLoopInterior(id: "missing", value: true))) {
                XCTAssertEqual($0 as? DocumentError, .missingPart("missing"))
            }
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
        }
    }
}
