import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class OriginProjectionTests: XCTestCase {
    func testFitIncludesSupportedOriginNodesAndReferenceInBothPlanes() throws {
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: -2, y: 3, z: 1), radius: 0.1))
        let nodes = try document.editorContents().nodes
        for origin in [
            NodePosition(x: 5, y: -4, z: 7), .init(x: -5, y: 8, z: -9), .init(x: 1_000_000, y: -1_000_000, z: 0),
        ] {
            for plane in EditingPlane.allCases {
                let projection = CanvasProjection(
                    bounds: CanvasBounds(nodes: nodes, referenceImageAspectRatio: 2, origin: origin), plane: plane,
                    width: 600, height: 400)
                for position in [origin, nodes[0].value.position, .init(x: 0, y: 0, z: 0), .init(x: 2, y: 1, z: 2)] {
                    let point = projection.point(for: position)
                    XCTAssertTrue((35.999...564.001).contains(point.x))
                    XCTAssertTrue((35.999...364.001).contains(point.y))
                }
            }
        }
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(
                bounds: CanvasBounds(nodes: [], origin: .init(x: 5, y: -4, z: 7)), plane: plane, width: 600, height: 400
            )
            let point = projection.point(for: .init(x: 5, y: -4, z: 7))
            XCTAssertTrue((0...600).contains(point.x))
            XCTAssertTrue((0...400).contains(point.y))
        }
    }
    func testInvalidOriginInputsDoNotCorruptBoundsOrIncludeHiddenNodes() throws {
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: -200, y: 300, z: 100), radius: 0.1)
        )
        .applying(.setPartState(id: "p", property: .visible, value: false))
        let nodes = try document.editorContents().nodes
        for plane in EditingPlane.allCases {
            let baseline = CanvasProjection(bounds: CanvasBounds(nodes: []), plane: plane, width: 600, height: 400)
            for origin in [
                NodePosition(x: .nan, y: 0, z: 0), .init(x: 0, y: .infinity, z: 0), .init(x: 0, y: 0, z: -1_000_001),
            ] {
                let projection = CanvasProjection(
                    bounds: CanvasBounds(nodes: nodes, origin: origin), plane: plane, width: 600, height: 400)
                XCTAssertEqual(projection.scale, baseline.scale)
                XCTAssertEqual(
                    projection.point(for: .init(x: 0, y: 0, z: 0)), baseline.point(for: .init(x: 0, y: 0, z: 0)))
            }
        }
    }
}
