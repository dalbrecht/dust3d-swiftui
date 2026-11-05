import Dust3DDocument
import Foundation
import XCTest

final class HollowArchiveTests: XCTestCase {
    func testPartRenameAndReopenPreserveHollowThickness() throws {
        let xml = "<canvas><parts><part id='p' hollowThickness='0.625'/></parts></canvas>"
        let document = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        let renamed = try document.applying(.setPartName(id: "p", name: "Tube"))
        let reopened = try Dust3DDocument(data: renamed.encoded())
        let model = try XMLDocument(data: reopened.modelXML)
        let part = try XCTUnwrap(model.nodes(forXPath: "/canvas/parts/part").first as? XMLElement)
        XCTAssertEqual(part.attribute(forName: "name")?.stringValue, "Tube")
        XCTAssertEqual(try reopened.partHollowThicknessSource(id: "p"), "0.625")
    }

    func testHollowEditStoresValueAndSolidEndpoint() throws {
        let xml = "<canvas><parts><part id='p'/></parts></canvas>"
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        XCTAssertNil(try original.partHollowThicknessSource(id: "p"))
        XCTAssertThrowsError(try original.partHollowThicknessSource(id: "missing"))
        let command = DocumentCommand.setPartHollowThickness(id: "p", thickness: 0.5)
        let edited = try original.applying(command)
        let model = try XMLDocument(data: edited.modelXML)
        let part = try XCTUnwrap(model.nodes(forXPath: "/canvas/parts/part").first as? XMLElement)
        XCTAssertEqual(part.attribute(forName: "hollowThickness")?.stringValue, "0.5")
        XCTAssertEqual(try edited.applying(command).modelXML, edited.modelXML)
        let solid = try edited.applying(.setPartHollowThickness(id: "p", thickness: 1))
        let reopened = try Dust3DDocument(data: solid.encoded())
        XCTAssertEqual(try reopened.partHollowThicknessSource(id: "p").flatMap(Double.init), 1)
        XCTAssertEqual(try solid.applying(.setPartHollowThickness(id: "p", thickness: 1)).encoded(), solid.encoded())
    }

    func testLegacyEndpointSurvivesUnrelatedEdit() throws {
        let xml = "<canvas><parts><part id='p' hollowThickness='1'/></parts></canvas>"
        let document = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        let renamed = try document.applying(.setPartName(id: "p", name: "Tube"))
        let reopened = try Dust3DDocument(data: renamed.encoded())
        XCTAssertEqual(try reopened.partHollowThicknessSource(id: "p"), "1")
    }

    func testClearHollowAndRejectInvalidValues() throws {
        let xml = "<canvas><parts><part id='p' hollowThickness='0.5'/></parts></canvas>"
        let document = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        for value in [Double.nan, .infinity, -0.1, 1.1] {
            XCTAssertThrowsError(try document.applying(.setPartHollowThickness(id: "p", thickness: value))) {
                XCTAssertEqual($0 as? DocumentError, .invalidPartHollowThickness)
            }
        }
        let cleared = try document.applying(.setPartHollowThickness(id: "p", thickness: 0))
        XCTAssertNil(try cleared.partHollowThicknessSource(id: "p"))
    }
}
