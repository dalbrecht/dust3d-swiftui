import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class CutFacePresetPreviewTests: XCTestCase {
    func testSquareMatchesPinnedOrderedVerticesAtFloatPrecision() {
        let presets: [(CutFacePreset, [(Float, Float)])] = [
            (.quad, [(-1, -1), (1, -1), (1, 1), (-1, 1)]),
            (.triangle, [(-1.1527, -0.6655), (1.1527, -0.6655), (0, 1.33447)]),
            (
                .pentagon,
                [(-0.6498, -0.8944), (0.6498, -0.8944), (1.05146, 0.34164), (0, 1.10557), (-1.05146, 0.34164)]
            ),
            (.hexagon, [(-0.577, -1), (0.577, -1), (1.1547, 0), (0.577, 1), (-0.577, 1), (-1.1547, 0)]),
        ]
        for (preset, vertices) in presets {
            let points = CutFacePresetPreview.points(for: preset, width: 20, height: 20)
            XCTAssertEqual(points.count, vertices.count, preset.rawValue)
            for (point, vertex) in zip(points, vertices) {
                XCTAssertEqual(point.x, (0.5 + 0.35 * Double(vertex.0)) * 20, accuracy: 1e-12, preset.rawValue)
                XCTAssertEqual(point.y, (0.5 - 0.35 * Double(vertex.1)) * 20, accuracy: 1e-12, preset.rawValue)
            }
        }
    }

    func testRectanglesCenterTheSameSquareWithoutDistortingIt() {
        XCTAssertEqual(
            CutFacePresetPreview.points(for: .quad, width: 40, height: 20),
            [.init(x: 13, y: 17), .init(x: 27, y: 17), .init(x: 27, y: 3), .init(x: 13, y: 3)])
        XCTAssertEqual(
            CutFacePresetPreview.points(for: .quad, width: 20, height: 40),
            [.init(x: 3, y: 27), .init(x: 17, y: 27), .init(x: 17, y: 13), .init(x: 3, y: 13)])
    }

    func testInvalidSizesProduceNoPoints() {
        for invalid in [0, -1, Double.nan, .infinity, -.infinity] {
            XCTAssertTrue(CutFacePresetPreview.points(for: .triangle, width: invalid, height: 20).isEmpty)
            XCTAssertTrue(CutFacePresetPreview.points(for: .triangle, width: 20, height: invalid).isEmpty)
        }
    }
}
