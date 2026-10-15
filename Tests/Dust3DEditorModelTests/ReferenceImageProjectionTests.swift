import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class ReferenceImageProjectionTests: XCTestCase {
    func testReferenceImageFitsImageHeightNormalizedQtCoordinatesInBothPlanes() {
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(
                bounds: CanvasBounds(nodes: [], referenceImageAspectRatio: 2), plane: plane, width: 600, height: 400)
            let topLeft = projection.point(for: .init(x: 0, y: 0, z: 0))
            let bottomRight = projection.point(for: .init(x: 2, y: 1, z: 2))
            XCTAssertGreaterThan(bottomRight.y, topLeft.y)
            XCTAssertEqual(bottomRight.x - topLeft.x, 2 * projection.scale, accuracy: 0.0001)
            XCTAssertEqual(bottomRight.y - topLeft.y, projection.scale, accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(topLeft.x, 36)
            XCTAssertLessThanOrEqual(bottomRight.x, 564)
            XCTAssertGreaterThanOrEqual(topLeft.y, 36)
            XCTAssertLessThanOrEqual(bottomRight.y, 364)
            let moved = projection.moving(.init(x: 0, y: 0, z: 0), by: .init(x: 0, y: 20))
            XCTAssertEqual(moved.y, 20 / projection.scale, accuracy: 0.0001)
        }
    }
    func testPortraitReferenceAndInvalidRatiosHaveStableBounds() {
        let portrait = CanvasProjection(
            bounds: CanvasBounds(nodes: [], referenceImageAspectRatio: 0.5), plane: .front, width: 600, height: 400)
        let center = portrait.point(for: .init(x: 0.25, y: 0.5, z: 0))
        XCTAssertEqual(center.x, 300, accuracy: 0.0001)
        XCTAssertEqual(center.y, 200, accuracy: 0.0001)
        let fallback = CanvasProjection(bounds: CanvasBounds(nodes: []), plane: .front, width: 600, height: 400)
        for invalid in [0.0, -1, .nan, .infinity] {
            let projection = CanvasProjection(
                bounds: CanvasBounds(nodes: [], referenceImageAspectRatio: invalid), plane: .front, width: 600,
                height: 400)
            XCTAssertEqual(projection.scale, fallback.scale)
            XCTAssertEqual(projection.point(for: .init(x: 0, y: 0, z: 0)), fallback.point(for: .init(x: 0, y: 0, z: 0)))
        }
    }

    func testImageAndOutlyingNodesAreBothIncludedInFit() throws {
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: -1, y: -2, z: 3), radius: 0.1))
        let nodes = try document.editorContents().nodes
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(
                bounds: CanvasBounds(nodes: nodes, referenceImageAspectRatio: 2), plane: plane,
                width: 800, height: 600)
            for position in [nodes[0].value.position, .init(x: 0, y: 0, z: 0), .init(x: 2, y: 1, z: 2)] {
                let point = projection.point(for: position)
                XCTAssertGreaterThanOrEqual(point.x, 36 - 0.0001)
                XCTAssertLessThanOrEqual(point.x, 764 + 0.0001)
                XCTAssertGreaterThanOrEqual(point.y, 36 - 0.0001)
                XCTAssertLessThanOrEqual(point.y, 564 + 0.0001)
            }
        }
    }
}
