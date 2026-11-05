import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class ReferenceColorSamplingTests: XCTestCase {
    func testOwnedStraightRowsPreservePaddingAndHiddenRgbAfterCallerMutation() throws {
        var bytes = Data([10, 20, 30, 0, 99, 98, 97, 96, 40, 50, 60, 128])
        let raster = try ReferenceColorRaster(width: 1, height: 2, rowStride: 8, pixels: bytes)
        bytes[0] = 255
        var exported = raster.pixels
        exported[0] = 254
        XCTAssertEqual(exported[0], 254)
        XCTAssertEqual(raster.color(x: 0, y: 0), DocumentColor(red: 10, green: 20, blue: 30, alpha: 0))
        XCTAssertEqual(raster.color(x: 0, y: 1), DocumentColor(red: 40, green: 50, blue: 60, alpha: 128))
        XCTAssertNil(raster.color(x: -1, y: 0))
        XCTAssertNil(raster.color(x: 1, y: 0))
        XCTAssertNil(raster.color(x: 0, y: 2))
    }

    func testRejectsInvalidOrOverflowingDimensionsStrideAndPayloadBeforeCopy() throws {
        for (width, height, stride, bytes) in [
            (0, 1, 4, 4), (8193, 1, 4, 4), (8192, 8192, 32768, 4),
            (1, 1, 3, 4), (1, 2, Int.max, 4), (2, 2, 8, 15), (1, 1, 4, 5),
        ] {
            XCTAssertThrowsError(
                try ReferenceColorRaster(
                    width: width, height: height, rowStride: stride, pixels: Data(repeating: 0, count: bytes)))
        }
    }

    func testFinalRowMayRetainItsBoundedPadding() throws {
        let bytes = Data([1, 2, 3, 4, 90, 90, 90, 90, 5, 6, 7, 8, 91, 91, 91, 91])
        let raster = try ReferenceColorRaster(width: 1, height: 2, rowStride: 8, pixels: bytes)
        XCTAssertEqual(raster.color(x: 0, y: 1), .init(red: 5, green: 6, blue: 7, alpha: 8))
    }

    func testFrontAndSideMapThroughExactlyDisplayedWholeReferenceRectangle() throws {
        let reference = try ReferencePixelSize(width: 8, height: 4)
        let raster = try ReferenceColorRaster(
            width: 4, height: 2, rowStride: 16,
            pixels: Data((0..<8).flatMap { [UInt8($0), 0, 0, 255] }))
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='outlier' x='-5' y='3' z='8' radius='.1'/></nodes><edges/><parts/><components/></canvas>"
                    .utf8))
        let nodes = try document.editorContents().nodes
        for plane in [EditingPlane.front, .side] {
            for view in [(500.0, 400.0), (900.0, 700.0)] {
                let projection = CanvasProjection(
                    bounds: .init(nodes: nodes, referenceImageAspectRatio: 2), plane: plane, width: view.0,
                    height: view.1)
                let layout = try ReferenceColorSamplingLayout(referenceSize: reference, projection: projection)
                let position = NodePosition(x: 1.25, y: 0.75, z: 0.25)
                let point = projection.point(for: position)
                XCTAssertEqual(layout.color(at: point, in: raster)?.red, plane == .front ? 6 : 4)
                XCTAssertNil(layout.color(at: projection.point(for: .init(x: 2, y: 0.5, z: 2)), in: raster))
                XCTAssertNil(layout.color(at: projection.point(for: .init(x: 0.5, y: 1, z: 0.5)), in: raster))
                XCTAssertNil(layout.color(at: projection.point(for: .init(x: -0.01, y: 0, z: -0.01)), in: raster))
                XCTAssertNil(layout.color(at: .init(x: .nan, y: 0), in: raster))
                XCTAssertEqual(layout.color(at: projection.point(for: .init(x: 0, y: 0, z: 0)), in: raster)?.red, 0)
                let first = projection.point(for: .init(x: 0, y: 0, z: 0))
                XCTAssertNil(layout.color(at: .init(x: first.x.nextDown, y: first.y), in: raster))
                XCTAssertNil(layout.color(at: .init(x: first.x, y: first.y.nextDown), in: raster))
                XCTAssertNil(
                    layout.color(
                        for: .init(x: -Double.leastNonzeroMagnitude, y: 0, z: -Double.leastNonzeroMagnitude), in: raster
                    ))
                XCTAssertNil(layout.color(for: .init(x: 2, y: 0, z: 2), in: raster))
                XCTAssertNil(layout.color(for: .init(x: 0, y: 1, z: 0), in: raster))
            }
        }
    }

    func testNearestQuantizationUsesExplicitFittedRasterNotImplicitBackingScale() throws {
        let size = try ReferencePixelSize(width: 2, height: 1)
        let projection = CanvasProjection(
            bounds: .init(nodes: [], referenceImageAspectRatio: 2), plane: .front, width: 500, height: 400)
        let layout = try ReferenceColorSamplingLayout(referenceSize: size, projection: projection)
        let one = try ReferenceColorRaster(
            width: 2, height: 1, rowStride: 8, pixels: Data([10, 0, 0, 255, 20, 0, 0, 255]))
        let two = try ReferenceColorRaster(
            width: 4, height: 2, rowStride: 16, pixels: Data((0..<8).flatMap { [UInt8($0), 0, 0, 255] }))
        let point = projection.point(for: .init(x: 0.99, y: 0.75, z: 0))
        XCTAssertEqual(layout.color(at: point, in: one)?.red, 10)
        XCTAssertEqual(layout.color(at: point, in: two)?.red, 5)
        XCTAssertEqual(layout.color(at: projection.point(for: .init(x: 1, y: 0, z: 0)), in: one)?.red, 20)
    }

    func testInvalidProjectionCannotCreateSamplingLayout() throws {
        let size = try ReferencePixelSize(width: 1, height: 1)
        let projection = CanvasProjection(bounds: .init(nodes: []), plane: .front, width: .infinity, height: 400)
        XCTAssertThrowsError(try ReferenceColorSamplingLayout(referenceSize: size, projection: projection))
    }
}
