import Dust3DDocument
import Foundation
import XCTest

final class PartTargetTests: XCTestCase {
    private func document(_ target: String? = nil) throws -> Dust3DDocument {
        let attributes = target.map { "target='\($0)'" } ?? ""
        let model = Data(
            "<canvas><nodes><node id='n' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p' locked='true' visible='false' disabled='true' future='keep' \(attributes)/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testKnownDefaultAndUnsupportedTargetsAreReadWithoutNormalizingSource() throws {
        for text in [nil, "", "Model", "CutFace", "StitchingLine", "StitchingLoop", "ImportedModel", "future", "model"]
            as [String?]
        {
            let source = try document(text)
            let expected: PartTarget? = (text == nil || text == "") ? .model : PartTarget(rawValue: text ?? "")
            XCTAssertEqual(try source.editorContents().parts.first?.target, expected)
            XCTAssertEqual(try Dust3DDocument(data: source.encoded()).encoded(), source.encoded())
        }
    }

    func testRoleChangesPreserveGraphFlagsAssetsAndExactUndoRedo() throws {
        for target in PartTarget.allCases {
            let source = try document("future")
            var history = DocumentHistory(document: source)
            try history.apply(.setPartTarget(id: "p", target: target))
            let changed = history.document
            let part = try XCTUnwrap(changed.editorContents().parts.first)
            XCTAssertEqual(part.target, target)
            XCTAssertTrue(part.isLocked)
            XCTAssertTrue(part.isDisabled)
            XCTAssertFalse(part.isVisible)
            XCTAssertEqual(try changed.editorContents().nodes, try source.editorContents().nodes)
            XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            let xml = try XMLDocument(data: changed.modelXML)
            let element = try XCTUnwrap(try xml.nodes(forXPath: "//part").first as? XMLElement)
            XCTAssertEqual(element.attribute(forName: "future")?.stringValue, "keep")
            XCTAssertEqual(element.attribute(forName: "target")?.stringValue, target == .model ? nil : target.rawValue)
            XCTAssertEqual(
                try Dust3DDocument(data: changed.encoded()).editorContents().parts, try changed.editorContents().parts)
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
    }

    func testSemanticNoOpsPreserveSourceSpellingsAndRedoAndMissingPartsReject() throws {
        for text in [nil, "", "Model", "CutFace", "StitchingLine", "StitchingLoop"] as [String?] {
            let source = try document(text)
            let target = try XCTUnwrap(source.editorContents().parts.first?.target)
            var history = DocumentHistory(document: source)
            try history.apply(.setPartName(id: "p", name: "Temporary"))
            XCTAssertTrue(history.undo())
            try history.apply(.setPartTarget(id: "p", target: target))
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
            XCTAssertThrowsError(try history.apply(.setPartTarget(id: "missing", target: .cutFace))) {
                XCTAssertEqual($0 as? DocumentError, .missingPart("missing"))
            }
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
        }
    }
}
