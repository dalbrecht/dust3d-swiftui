import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

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

    func testOrbitProjectsAQuarterTurnAndDrawsDepthTiesInSourceOrder() throws {
        let xml = """
            <rig type="Test">
                <bone name="Near"><position x="0" y="0" z="1"/><endPosition x="0" y="1" z="1"/></bone>
                <bone name="Far"><position x="0" y="0" z="-1"/><endPosition x="0" y="1" z="-1"/></bone>
                <bone name="Far second"><position x="0" y="1" z="-1"/><endPosition x="0" y="2" z="-1"/></bone>
            </rig>
            """
        let hierarchy = try RigTemplateHierarchy.parse(Data(xml.utf8), expectedType: "Test")
        let front = RigTemplateDiagramLayout.lines(in: hierarchy, orbit: .init(), width: 220, height: 120)
        XCTAssertEqual(front.map(\.name), ["Far", "Far second", "Near"])
        XCTAssertEqual(front.last?.start.x, 110)
        let turned = RigTemplateDiagramLayout.lines(
            in: hierarchy, orbit: RigTemplateOrbit().rotated(yaw: .pi / 2, pitch: 0), width: 220, height: 120)
        let near = try XCTUnwrap(turned.first { $0.name == "Near" })
        let far = try XCTUnwrap(turned.first { $0.name == "Far" })
        XCTAssertGreaterThan(near.start.x, 110)
        XCTAssertLessThan(far.start.x, 110)
        XCTAssertEqual(near.start.y, front.last?.start.y)
    }

    func testOrbitBoundsAndInvalidRotationNeverEscapeTheViewport() throws {
        let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let start = RigTemplateOrbit()
        XCTAssertEqual(start.rotated(yaw: .nan, pitch: 1), start)
        let turned = start.rotated(yaw: .greatestFiniteMagnitude, pitch: .greatestFiniteMagnitude)
        XCTAssertTrue(turned.yaw.isFinite)
        XCTAssertLessThanOrEqual(abs(turned.yaw), 2 * .pi)
        XCTAssertLessThanOrEqual(abs(turned.pitch), .pi / 2)
        for orbit in [start, turned] {
            for size in [(30.0, 200.0), (200.0, 30.0)] {
                let lines = RigTemplateDiagramLayout.lines(
                    in: hierarchy, orbit: orbit, width: size.0, height: size.1)
                XCTAssertEqual(lines.count, hierarchy.bones.count)
                for line in lines {
                    for point in [line.start, line.end] {
                        XCTAssertTrue((0...size.0).contains(point.x))
                        XCTAssertTrue((0...size.1).contains(point.y))
                    }
                }
            }
        }
        XCTAssertTrue(RigTemplateDiagramLayout.lines(in: hierarchy, orbit: start, width: .nan, height: 100).isEmpty)
    }

    func testOrbitCentersTinySegmentsAtAnOffset() throws {
        let xml = """
            <rig type="Test">
                <bone name="Short"><position x="1" y="0" z="0"/><endPosition x="1.0000000000000002" y="0" z="0"/></bone>
            </rig>
            """
        let hierarchy = try RigTemplateHierarchy.parse(Data(xml.utf8), expectedType: "Test")
        let line = try XCTUnwrap(
            RigTemplateDiagramLayout.lines(in: hierarchy, orbit: .init(), width: 100, height: 100).first)
        XCTAssertEqual(line.start.x, 10, accuracy: 1e-9)
        XCTAssertEqual(line.end.x, 90, accuracy: 1e-9)
        XCTAssertEqual(line.start.y, 50, accuracy: 1e-9)
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
