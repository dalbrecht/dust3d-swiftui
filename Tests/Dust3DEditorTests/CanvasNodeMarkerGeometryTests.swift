import Dust3DEditorModel
import XCTest

final class CanvasNodeMarkerGeometryTests: XCTestCase {
    func testSmallestHoveredRingClearsTheOpaqueCenter() {
        let marker = CanvasNodeMarkerGeometry(projectedDiameter: 1, selected: false, hovered: true)
        XCTAssertEqual(marker.outlineWidth, 3)
        XCTAssertEqual(marker.outlineDiameter, 16)
        XCTAssertGreaterThan(
            marker.outlineDiameter - marker.outlineWidth, CanvasNodeMarkerGeometry.centerDiameter)
        let unhovered = CanvasNodeMarkerGeometry(projectedDiameter: 1, selected: false, hovered: false)
        XCTAssertEqual(unhovered.outlineDiameter, 8)
        XCTAssertEqual(unhovered.outlineWidth, 1)
    }

    func testNormalAndLargeDiametersRetainTheirOutlineSizes() {
        let selected = CanvasNodeMarkerGeometry(projectedDiameter: 32, selected: true, hovered: false)
        XCTAssertEqual(selected.outlineDiameter, 32)
        XCTAssertEqual(selected.outlineWidth, 2)
        let hovered = CanvasNodeMarkerGeometry(projectedDiameter: 32, selected: true, hovered: true)
        XCTAssertEqual(hovered.outlineDiameter, 32)
        XCTAssertEqual(hovered.outlineWidth, 3)
        let large = CanvasNodeMarkerGeometry(projectedDiameter: 1_000, selected: false, hovered: true)
        XCTAssertEqual(large.outlineDiameter, 600)
        XCTAssertEqual(large.outlineWidth, 3)
    }
}
