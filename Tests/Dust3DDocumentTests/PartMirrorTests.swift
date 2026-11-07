import Dust3DDocument
import Foundation
import XCTest

final class PartMirrorTests: XCTestCase {
    private func source(_ flag: String = "", origin: String = "", role: String = "Model") throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas \(origin) future='keep'><nodes><node id='n' partId='p' x='2' y='.5' z='.5' radius='.5'/><node id='other' partId='q' x='-1' y='.5' z='.5' radius='.25'/></nodes><edges/><parts><part id='p' target='\(role)' locked='true' visible='false' disabled='true' future='keep' \(flag)/><part id='q'/></parts><components><component id='a' linkDataType='partId' linkData='p'/><component id='b' linkDataType='partId' linkData='p'/></components></canvas>"
                    .utf8))
    }
    func testTypedFlagsPreserveUnknownAndRawImportedRole() throws {
        for (text, expected) in [
            ("", Optional(false)), ("xMirrored=''", false), ("xMirrored='true'", true), ("xMirrored='True'", true),
            ("xMirrored='1'", true), ("xMirrored='false'", false), ("xMirrored='0'", false),
            ("xMirrored='future'", nil),
        ] {
            let doc = try source(text, role: "ImportedModel")
            let part = try XCTUnwrap(doc.editorContents().parts.first)
            XCTAssertEqual(part.xMirrored, expected)
            XCTAssertNil(part.target)
            XCTAssertEqual(try Dust3DDocument(data: doc.encoded()).encoded(), doc.encoded())
            XCTAssertTrue(String(decoding: doc.modelXML, as: UTF8.self).contains("ImportedModel"))
        }
    }
    func testChangeCentersOnlyUnavailableOriginAndUndoIsExactDespitePartFlags() throws {
        for role in ["Model", ""] {
            let doc = try source(role: role)
            var history = DocumentHistory(document: doc)
            let before = history.previewIdentity
            try history.apply(.setPartXMirrored(id: "p", value: true))
            let after = history.document
            XCTAssertEqual(try after.origin(), .init(x: 0.625, y: 0.5, z: 0.5))
            XCTAssertEqual(try after.editorContents().parts.first?.xMirrored, true)
            XCTAssertEqual(try after.editorContents().nodes, try doc.editorContents().nodes)
            XCTAssertNotEqual(history.previewIdentity.geometry, before.geometry)
            XCTAssertNotEqual(history.previewIdentity.materials, before.materials)
            history.undo()
            XCTAssertEqual(history.document.encoded(), doc.encoded())
            XCTAssertFalse(history.canUndo)
            history.redo()
            XCTAssertEqual(history.document.encoded(), after.encoded())
        }
    }
    func testUnsupportedOriginAndFlagRepairAreFieldLocalAndEmptyGraphSettlesToSupportedZero() throws {
        let original = try source(
            "xMirrored='future'", origin: "originX='future' originY='0' originZ='0'")
        let repaired = try original.applying(.setPartXMirrored(id: "p", value: false))
        XCTAssertEqual(try repaired.origin(), .init(x: 0.625, y: 0.5, z: 0.5))
        let xml = String(decoding: repaired.modelXML, as: UTF8.self)
        let root = try XCTUnwrap(XMLDocument(data: repaired.modelXML).rootElement())
        XCTAssertEqual(root.attribute(forName: "future")?.stringValue, "keep")
        XCTAssertFalse(xml.contains("xMirrored="))
        let empty = try Dust3DDocument(
            snapshotXML: Data("<canvas><nodes/><edges/><parts><part id='p'/></parts><components/></canvas>".utf8))
        let changed = try empty.applying(.setPartXMirrored(id: "p", value: true))
        XCTAssertEqual(try changed.origin(), .init(x: 0, y: 0, z: 0))
    }
    func testUnsupportedRolesRejectEditsAndRetainAuthoredMetadata() throws {
        for role in ["ImportedModel", "CutFace", "StitchingLine", "StitchingLoop", "Future"] {
            let doc = try source("xMirrored='future'", role: role)
            XCTAssertThrowsError(try doc.applying(.setPartXMirrored(id: "p", value: true))) {
                XCTAssertEqual($0 as? DocumentError, .invalidPartMirrorRole)
            }
            XCTAssertNil(try doc.editorContents().parts.first?.xMirrored)
            XCTAssertNil(try doc.origin())
        }
    }

    func testNoopDoesNotSettleOriginAndExplicitZeroIsRetained() throws {
        let original = try source("xMirrored='0'")
        XCTAssertEqual(try original.applying(.setPartXMirrored(id: "p", value: false)).encoded(), original.encoded())
        XCTAssertNil(try original.origin())
        let zero = try source(origin: "originX='0' originY='0' originZ='0'")
        let mirrored = try zero.applying(.setPartXMirrored(id: "p", value: true))
        XCTAssertEqual(try mirrored.origin(), .init(x: 0, y: 0, z: 0))
        XCTAssertThrowsError(try zero.applying(.setPartXMirrored(id: "missing", value: true)))
        let off = try mirrored.applying(.setPartXMirrored(id: "p", value: false))
        XCTAssertEqual(try off.editorContents().parts.first?.xMirrored, false)
        XCTAssertFalse(String(decoding: off.modelXML, as: UTF8.self).contains("xMirrored="))
    }
}
