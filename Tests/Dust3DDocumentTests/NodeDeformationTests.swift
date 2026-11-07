import Dust3DDocument
import Foundation
import XCTest

final class NodeDeformationTests: XCTestCase {
    private func makeDocument(nodeAttributes: String = "", partAttributes: String = "") throws -> Dust3DDocument {
        let xml = """
            <canvas future='keep'><nodes>
            <node id='a' partId='p' x='1.00' y='2' z='3' radius='.25' future='opaque' \(nodeAttributes)>
            <vendor>keep</vendor><!--node-comment-->
            </node>
            <node id='b' partId='p' x='4' y='5' z='6' radius='.5' deformWidth='1.25'/>
            </nodes><parts><part id='p' \(partAttributes)/></parts></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }

    func testMissingScalesDefaultToOneAndUnsupportedSourceIsRetained() throws {
        let source = try makeDocument()
        XCTAssertEqual(try node(in: source).deformationScale(.width), 1)
        XCTAssertEqual(try node(in: source).deformationScale(.thickness), 1)
        for raw in ["", "unsupported", "0", "-1", "1e-100", "1000001"] {
            let imported = try makeDocument(nodeAttributes: "deformWidth='\(raw)' deformThickness='0.75'")
            let bytes = imported.encoded()
            XCTAssertNil(try node(in: imported).deformationScale(.width), raw)
            XCTAssertEqual(try node(in: imported).deformationScale(.thickness), 0.75)
            XCTAssertEqual(imported.encoded(), bytes)
        }
    }

    func testEditOneScalePreservesNodeGeometryAndUnknownDataWithExactNoOp() throws {
        let source = try makeDocument(nodeAttributes: "deformWidth='unsupported' deformThickness='.75'")
        let edited = try source.applying(.setNodeDeformationScale(id: "a", property: .width, value: 2.5))
        XCTAssertEqual(try node(in: edited).deformationScale(.width), 2.5)
        XCTAssertEqual(try node(in: edited).deformationScale(.thickness), 0.75)
        XCTAssertEqual(try edited.node(id: "a"), try source.node(id: "a"))
        XCTAssertEqual(try node(in: edited, id: "b"), try node(in: source, id: "b"))
        let model = try XMLDocument(data: edited.modelXML)
        let element = try XCTUnwrap(model.nodes(forXPath: "//node[@id='a']").first as? XMLElement)
        XCTAssertEqual(element.attribute(forName: "x")?.stringValue, "1.00")
        XCTAssertEqual(element.attribute(forName: "deformThickness")?.stringValue, ".75")
        XCTAssertEqual(element.attribute(forName: "future")?.stringValue, "opaque")
        XCTAssertEqual(element.elements(forName: "vendor").first?.stringValue, "keep")
        XCTAssertTrue(element.xmlString.contains("<!--node-comment-->"))
        XCTAssertEqual(model.rootElement()?.attribute(forName: "future")?.stringValue, "keep")

        let repeated = try edited.applying(.setNodeDeformationScale(id: "a", property: .width, value: 2.5))
        XCTAssertEqual(repeated.encoded(), edited.encoded())

        let reset = try edited.applying(.setNodeDeformationScale(id: "a", property: .width, value: 1))
        XCTAssertEqual(try node(in: reset).deformationScale(.width), 1)
        let resetModel = try XMLDocument(data: reset.modelXML)
        let resetElement = try XCTUnwrap(resetModel.nodes(forXPath: "//node[@id='a']").first as? XMLElement)
        XCTAssertNil(resetElement.attribute(forName: "deformWidth"))
        XCTAssertEqual(resetElement.attribute(forName: "deformThickness")?.stringValue, ".75")
    }

    func testRejectsInvalidValuesAndNodesOutsideEditableModelParts() throws {
        let source = try makeDocument()
        for invalid in [0.0, -1, .nan, .infinity, -.infinity, 1e-100, 1_000_001] {
            XCTAssertThrowsError(
                try source.applying(.setNodeDeformationScale(id: "a", property: .width, value: invalid)))
        }
        let maximum = try source.applying(.setNodeDeformationScale(id: "a", property: .thickness, value: 1_000_000))
        XCTAssertEqual(try node(in: maximum).deformationScale(.thickness), 1_000_000)

        for attributes in ["locked='true'", "visible='false'", "disabled='true'", "target='CutFace'"] {
            let rejected = try makeDocument(partAttributes: attributes)
            XCTAssertThrowsError(
                try rejected.applying(.setNodeDeformationScale(id: "a", property: .width, value: 2)), attributes)
        }
        XCTAssertThrowsError(try source.applying(.setNodeDeformationScale(id: "missing", property: .width, value: 2)))
    }

    private func node(in document: Dust3DDocument, id: String = "a") throws -> DocumentNode {
        try XCTUnwrap(document.editorContents().nodes.first { $0.id == id })
    }
}
