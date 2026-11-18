import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class CanvasLassoTests: XCTestCase {
    private func polygon(_ vertices: [(Double, Double)]) -> CanvasLasso {
        var path = CanvasLasso()
        for (x, y) in vertices { path.append(.init(x: x, y: y)) }
        return path
    }

    func testConcaveShapeIncludesBoundaryAndExcludesBoundingBoxNotch() {
        let path = polygon([(0, 0), (30, 0), (30, 10), (10, 10), (10, 30), (0, 30)])
        XCTAssertTrue(path.contains(.init(x: 5, y: 20)))
        XCTAssertTrue(path.contains(.init(x: 20, y: 5)))
        XCTAssertTrue(path.contains(.init(x: 10, y: 20)))
        XCTAssertFalse(path.contains(.init(x: 20, y: 20)))
    }

    func testSelfIntersectionUsesOddEvenFillAndIncludesBoundary() {
        let bowTie = polygon([(0, 0), (30, 30), (0, 30), (30, 0)])
        XCTAssertTrue(bowTie.contains(.init(x: 15, y: 5)))
        XCTAssertTrue(bowTie.contains(.init(x: 15, y: 25)))
        XCTAssertTrue(bowTie.contains(.init(x: 15, y: 15)))
        XCTAssertFalse(bowTie.contains(.init(x: 5, y: 15)))
        let twice = polygon([(0, 0), (30, 0), (30, 30), (0, 30), (0, 0), (30, 0), (30, 30), (0, 30)])
        XCTAssertFalse(twice.contains(.init(x: 15, y: 15)))
        XCTAssertTrue(twice.contains(.init(x: 0, y: 15)))
    }

    func testCrossingAndTouchingStrokesAndCollapsedProjection() {
        let path = polygon([(10, 10), (20, 10), (20, 20), (10, 20)])
        XCTAssertTrue(path.intersectsStroke(from: .init(x: 0, y: 15), to: .init(x: 30, y: 15), halfWidth: 1))
        XCTAssertFalse(path.intersectsStroke(from: .init(x: 0, y: 8), to: .init(x: 30, y: 8), halfWidth: 1))
        XCTAssertTrue(path.intersectsStroke(from: .init(x: 0, y: 8), to: .init(x: 30, y: 8), halfWidth: 2))
        XCTAssertTrue(path.intersectsStroke(from: .init(x: 9, y: 15), to: .init(x: 9, y: 15), halfWidth: 1))
        XCTAssertFalse(path.intersectsStroke(from: .init(x: 8, y: 15), to: .init(x: 8, y: 15), halfWidth: 1))
    }

    func testSamplingIsBoundedAndTwoPointsUseRectangle() {
        var path = CanvasLasso()
        path.append(.init(x: 0, y: 0))
        path.append(.init(x: 0.5, y: 0.5))
        path.append(.init(x: .nan, y: 1))
        path.append(.init(x: 10, y: 20))
        XCTAssertEqual(path.points, [.init(x: 0, y: 0), .init(x: 10, y: 20)])
        XCTAssertTrue(path.contains(.init(x: 8, y: 2)))
        XCTAssertFalse(path.contains(.init(x: 11, y: 2)))
        for i in 1...CanvasLasso.maximumPointCount * 3 {
            path.append(.init(x: Double(i) * 3 + 10, y: 0))
        }
        XCTAssertLessThanOrEqual(path.points.count, CanvasLasso.maximumPointCount)
        XCTAssertEqual(path.points.first, .init(x: 0, y: 0))
        XCTAssertEqual(path.points.last?.x, Double(CanvasLasso.maximumPointCount * 9 + 10))
    }

    func testProjectionIntersectsVisibleNodeCirclesInBothProfiles() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='visible' partId='p' x='0' y='0' z='0' radius='.25'/>
                <node id='hidden' partId='h' x='0' y='0' z='0' radius='.25'/>
                </nodes><parts><part id='p'/><part id='h' visible='false'/></parts></canvas>
                """.utf8))
        let nodes = try document.editorContents().nodes
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(bounds: .init(nodes: nodes), plane: plane, width: 400, height: 300)
            let center = projection.point(for: .init(x: 0, y: 0, z: 0))
            let radius = 0.25 * projection.scale
            let x = center.x + radius - 2
            let y = center.y
            let rectangle = polygon([(x, y - 4), (x + 4, y + 4)])
            let shape = polygon([(x, y - 4), (x + 4, y - 4), (x + 4, y + 4), (x, y + 4)])
            let corner = polygon([
                (center.x + radius * 0.8, y + radius * 0.8),
                (center.x + radius, y + radius * 0.8),
                (center.x + radius, y + radius),
            ])
            XCTAssertEqual(projection.nodeIDs(in: rectangle, nodes: nodes), ["visible"])
            XCTAssertEqual(projection.nodeIDs(in: shape, nodes: nodes), ["visible"])
            XCTAssertTrue(projection.nodeIDs(in: corner, nodes: nodes).isEmpty)
            let tangentX = center.x + radius
            let tangent = polygon([
                (tangentX, y - 4), (tangentX + 4, y - 4), (tangentX + 4, y + 4), (tangentX, y + 4),
            ])
            XCTAssertTrue(projection.nodeIDs(in: tangent, nodes: nodes).isEmpty, "\(plane)")
        }
    }

    func testPreviewUsesTheFrozenPicksForEachPressIntent() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='1' y='0' z='1' radius='.1'/>
                <node id='c' partId='p' x='2' y='0' z='2' radius='.1'/>
                </nodes><edges>
                <edge id='ab' partId='p' from='a' to='b'/>
                <edge id='bc' partId='p' from='b' to='c'/>
                </edges><parts><part id='p'/></parts></canvas>
                """.utf8))
        let contents = try document.editorContents()
        let projection = CanvasProjection(bounds: .init(nodes: contents.nodes), plane: .side, width: 400, height: 300)
        let center = projection.point(for: .init(x: 0, y: 0, z: 0))
        let near = polygon([(center.x - 5, center.y - 5), (center.x + 5, center.y + 5)])
        let far = polygon([(center.x - 50, center.y - 50), (center.x - 40, center.y - 40)])
        for (mode, nodes, edges): (GraphSelectionMode, Set<String>, Set<String>) in [
            (.replace, ["a"], ["ab"]),
            (.add, ["a", "b"], ["ab", "bc"]),
            (.toggle, ["b"], ["bc"]),
            (.subtract, ["b"], ["bc"]),
        ] {
            let initiallySelected: CanvasLassoPickPlan.Picks =
                mode == .toggle || mode == .subtract ? (["a", "b"], ["ab", "bc"]) : (["b"], ["bc"])
            let plan = CanvasLassoPickPlan(
                projection: projection, nodes: contents.nodes, edges: contents.edges,
                selected: initiallySelected, mode: mode, includesNodes: true)
            XCTAssertEqual(plan.preview(in: near).nodes, nodes)
            XCTAssertEqual(plan.preview(in: near).edges, edges)
            XCTAssertEqual(plan.preview(in: far).nodes, mode == .replace ? [] : initiallySelected.nodes)
            XCTAssertEqual(plan.preview(in: far).edges, mode == .replace ? [] : initiallySelected.edges)
        }

        let rig = CanvasLassoPickPlan(
            projection: projection, nodes: contents.nodes, edges: contents.edges,
            selected: ([], []), mode: .replace, includesNodes: false)
        XCTAssertTrue(rig.preview(in: near).nodes.isEmpty)
        XCTAssertEqual(rig.preview(in: near).edges, ["ab"])
    }

    func testProjectionSelectsVisibleNodeCentersAndExplicitCrossingEdgesInBothProfiles() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='inside' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='a' partId='p' x='-2' y='0' z='-2' radius='.1'/>
                <node id='b' partId='p' x='2' y='0' z='2' radius='.1'/>
                <node id='c' partId='hidden' x='-2' y='.1' z='-2' radius='.1'/>
                <node id='d' partId='hidden' x='2' y='.1' z='2' radius='.1'/>
                </nodes><edges><edge id='cross' partId='p' from='a' to='b'/>
                <edge id='hidden-edge' partId='hidden' from='c' to='d'/></edges>
                <parts><part id='p'/><part id='hidden' visible='false'/></parts></canvas>
                """.utf8))
        let contents = try document.editorContents()
        for plane in [EditingPlane.front, .side] {
            let projection = CanvasProjection(
                bounds: .init(nodes: contents.nodes), plane: plane, width: 400, height: 300)
            let center = projection.point(for: .init(x: 0, y: 0, z: 0))
            let path = polygon([
                (center.x - 10, center.y - 10), (center.x + 10, center.y - 10),
                (center.x + 10, center.y + 10), (center.x - 10, center.y + 10),
            ])
            XCTAssertEqual(projection.nodeIDs(in: path, nodes: contents.nodes), ["inside"])
            XCTAssertEqual(projection.edgeIDs(in: path, nodes: contents.nodes, edges: contents.edges), ["cross"])
        }
    }
}
