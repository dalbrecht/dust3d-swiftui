import Dust3DEditorModel
import Dust3DKit
import XCTest

@testable import Dust3DEditor

final class RigTemplateDiagramLayoutTests: XCTestCase {
    func testFrontAndSideFitAndPreserveTheAuthoredVerticalDirection() throws {
        let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let front = RigTemplateDiagramLayout.lines(in: hierarchy, plane: .front, width: 220, height: 120)
        let side = RigTemplateDiagramLayout.lines(in: hierarchy, plane: .side, width: 220, height: 120)
        XCTAssertEqual(front.count, hierarchy.bones.count)
        XCTAssertEqual(side.map(\.name), front.map(\.name))
        XCTAssertNotEqual(front, side)
        for line in front + side {
            for point in [line.start, line.end] {
                XCTAssertTrue((0...220).contains(point.x))
                XCTAssertTrue((0...120).contains(point.y))
            }
        }
        let root = try XCTUnwrap(front.first { $0.name == "Root" })
        XCTAssertEqual(root.start.x, root.end.x)
        XCTAssertGreaterThan(root.start.y, root.end.y)
    }

    func testHighlightUsesExactNamesAndInvalidViewportProducesNoLines() throws {
        let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let lines = RigTemplateDiagramLayout.lines(in: hierarchy, plane: .side, width: 200, height: 100)
        let root = try XCTUnwrap(lines.first { $0.name == "Root" })
        XCTAssertTrue(root.isSelected("Root"))
        XCTAssertFalse(root.isSelected("root"))
        XCTAssertFalse(root.isSelected(nil))
        let spelling = RigTemplateDiagramLayout.Line(name: "é", start: root.start, end: root.end)
        XCTAssertTrue(spelling.isSelected("é"))
        XCTAssertFalse(spelling.isSelected("e\u{301}"))
        XCTAssertTrue(
            RigTemplateDiagramLayout.lines(in: hierarchy, plane: .front, width: .infinity, height: 100).isEmpty)
        XCTAssertTrue(RigTemplateDiagramLayout.lines(in: hierarchy, plane: .side, width: 100, height: 0).isEmpty)
    }
}
