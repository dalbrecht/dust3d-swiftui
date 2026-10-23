import Dust3DDocument
import Foundation
import XCTest

final class EdgeBoneBindingTests: XCTestCase {
    private func document(edgeAttributes: String = "", partAttributes: String = "") throws -> Dust3DDocument {
        let model = Data(
            "<canvas rigType='future'><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/><node id='b' partId='p' x='1' y='0' z='0' radius='.1'/></nodes><edges><edge id='e' from='a' to='b' future='keep' \(edgeAttributes)/></edges><parts><part id='p' \(partAttributes)/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components><rig future='retain'/></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testReadsExactLegacyNamesAndClearNoOpsWithoutNormalizingArchive() throws {
        for attributes in [
            "", "boneName=''", "boneName=' Root '", "boneName='FutureBone'", "boneName='Root &amp; &lt;Left&gt;'",
            "boneName='\(String(repeating: "x", count: 1025))'",
        ] {
            let source = try document(edgeAttributes: attributes)
            let xml = try XMLDocument(data: source.modelXML)
            let edge = try XCTUnwrap(try xml.nodes(forXPath: "//edge").first as? XMLElement)
            XCTAssertEqual(
                try source.editorContents().edges.first?.boneName,
                edge.attribute(forName: "boneName")?.stringValue ?? "")
            XCTAssertEqual(try Dust3DDocument(data: source.encoded()).encoded(), source.encoded())
            if attributes == "" || attributes == "boneName=''" {
                XCTAssertEqual(try source.applying(.setEdgeBoneName(id: "e", name: "")).encoded(), source.encoded())
            }
        }
    }

    func testAssignAndClearPreserveExactIdentityOpaqueDataAndHistory() throws {
        for name in ["Root", " Root ", "左腕 & <hand>", String(repeating: "é", count: 512), ""] {
            let source = try document(edgeAttributes: "boneName='FutureBone'")
            var history = DocumentHistory(document: source)
            try history.apply(.setEdgeBoneName(id: "e", name: name))
            let changed = history.document
            XCTAssertEqual(try changed.editorContents().edges.first?.boneName, name)
            XCTAssertEqual(try changed.editorContents().nodes, try source.editorContents().nodes)
            XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            let xml = try XMLDocument(data: changed.modelXML)
            let edge = try XCTUnwrap(try xml.nodes(forXPath: "//edge").first as? XMLElement)
            XCTAssertEqual(edge.attribute(forName: "future")?.stringValue, "keep")
            XCTAssertEqual(edge.attribute(forName: "boneName")?.stringValue, name.isEmpty ? nil : name)
            XCTAssertEqual(try xml.nodes(forXPath: "/canvas/rig[@future='retain']").count, 1)
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            try history.apply(.setEdgeBoneName(id: "e", name: "FutureBone"))
            XCTAssertTrue(history.canRedo)
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
            XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).editorContents().edges.first?.boneName, name)
        }
    }

    func testInvalidNamesMissingEdgesAndReadonlyEndpointsRejectWithoutHistory() throws {
        let source = try document()
        for name in [
            String(repeating: "é", count: 513), "a\n", "a\r", "a\t", "a\0", "a\u{7f}", "a\u{2028}", "a\u{ffff}",
            "a\u{fffe}",
        ] {
            var history = DocumentHistory(document: source)
            XCTAssertThrowsError(try history.apply(.setEdgeBoneName(id: "e", name: name))) {
                XCTAssertEqual($0 as? DocumentError, .invalidBoneName)
            }
            XCTAssertFalse(history.canUndo)
            XCTAssertEqual(history.document.encoded(), source.encoded())
        }
        XCTAssertThrowsError(try source.applying(.setEdgeBoneName(id: "missing", name: "Root"))) {
            XCTAssertEqual($0 as? DocumentError, .invalidNode)
        }
        for flags in ["locked='true'", "visible='false'", "disabled='true'"] {
            for readonlyFirst in [true, false] {
                let base = try document(partAttributes: readonlyFirst ? flags : "")
                let model = try XCTUnwrap(String(data: base.modelXML, encoding: .utf8))
                    .replacingOccurrences(of: "id='b' partId='p'", with: "id='b' partId='q'")
                    .replacingOccurrences(of: "</parts>", with: "<part id='q' \(readonlyFirst ? "" : flags)/></parts>")
                let readonly = try Dust3DDocument(snapshotXML: Data(model.utf8))
                XCTAssertThrowsError(try readonly.applying(.setEdgeBoneName(id: "e", name: "Root"))) {
                    XCTAssertEqual($0 as? DocumentError, .invalidNode)
                }
            }
        }
    }
}
