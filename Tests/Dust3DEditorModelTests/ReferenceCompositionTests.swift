import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class ReferenceCompositionTests: XCTestCase {
    func testPixelSizeAndCropRejectInvalidOrOverflowingBoundaries() throws {
        for (width, height) in [(0, 1), (1, -1), (8193, 1), (8192, 8192), (Int.max, Int.max)] {
            XCTAssertThrowsError(try ReferencePixelSize(width: width, height: height))
        }
        let size = try ReferencePixelSize(width: 100, height: 80)
        let full = ReferenceImageCrop(size: size)
        XCTAssertEqual(full.x, 0)
        XCTAssertEqual(full.y, 0)
        XCTAssertEqual(full.width, 100)
        XCTAssertEqual(full.height, 80)
        for values in [
            (-1, 0, 1, 1), (0, -1, 1, 1), (100, 0, 1, 1), (0, 80, 1, 1), (0, 0, 0, 1),
            (0, 0, 1, 0), (99, 79, 2, 1), (0, 0, Int.max, Int.max),
        ] {
            XCTAssertThrowsError(
                try ReferenceImageCrop(size: size, x: values.0, y: values.1, width: values.2, height: values.3))
        }
        let edge = try ReferenceImageCrop(size: size, x: 99, y: 79, width: 1, height: 1)
        XCTAssertEqual(edge.mirroredHorizontally.x, 0)
        XCTAssertEqual(edge.mirroredHorizontally.mirroredHorizontally, edge)
    }

    func testPointerCropNormalizesClampsAndRejectsEmptyWithoutOverflow() throws {
        let size = try ReferencePixelSize(width: 100, height: 80)
        let crop = try ReferenceImageCrop.between(x1: Int.max, y1: 70, x2: -20, y2: -10, size: size)
        XCTAssertEqual(crop, try ReferenceImageCrop(size: size, x: 0, y: 0, width: 100, height: 70))
        XCTAssertThrowsError(try ReferenceImageCrop.between(x1: -2, y1: 0, x2: -1, y2: 10, size: size))
        XCTAssertThrowsError(try ReferenceImageCrop.between(x1: 1, y1: Int.min, x2: 3, y2: -1, size: size))
    }

    func testCompositionPlacesProfilesInSeparateHalvesAndComputesOrigin() throws {
        let front = ReferenceImageCrop(size: try ReferencePixelSize(width: 1, height: 2))
        let side = ReferenceImageCrop(size: try ReferencePixelSize(width: 3, height: 2))
        let layout = try ReferenceCompositionLayout(front: front, side: side)
        XCTAssertEqual(layout.width, 1536)
        XCTAssertEqual(layout.height, 512)
        XCTAssertEqual(layout.front?.width, 256)
        XCTAssertEqual(layout.front?.x, 256)
        XCTAssertEqual(layout.side?.width, 768)
        XCTAssertEqual(layout.side?.x, 768)
        XCTAssertEqual(layout.origin, .init(x: 0.75, y: 0.5, z: 2.25))
        let swapped = try ReferenceCompositionLayout(front: side, side: front)
        XCTAssertEqual(swapped.front?.x, 0)
        XCTAssertEqual(swapped.side?.x, 1024)
        XCTAssertEqual(swapped.origin, layout.origin)
    }

    func testSingleProfilesOddRoundingThinCropsAndOutputLimits() throws {
        let odd = ReferenceImageCrop(size: try ReferencePixelSize(width: 1, height: 3))
        let front = try ReferenceCompositionLayout(front: odd, side: nil)
        XCTAssertEqual(front.width, 1024)
        XCTAssertEqual(front.front?.width, 171)
        XCTAssertEqual(front.front?.x, 170)
        XCTAssertNil(front.side)
        XCTAssertEqual(front.origin, .init(x: 255.5 / 512, y: 0.5, z: 1.5))
        let side = try ReferenceCompositionLayout(front: nil, side: odd)
        XCTAssertNil(side.front)
        XCTAssertEqual(side.side?.x, 682)
        XCTAssertEqual(side.origin, .init(x: 0.5, y: 0.5, z: 767.5 / 512))
        let thin = ReferenceImageCrop(size: try ReferencePixelSize(width: 1, height: 8192))
        XCTAssertEqual(try ReferenceCompositionLayout(front: thin, side: nil).front?.width, 1)
        let maximum = ReferenceImageCrop(size: try ReferencePixelSize(width: 8, height: 1))
        XCTAssertEqual(try ReferenceCompositionLayout(front: maximum, side: nil).width, 8192)
        let huge = ReferenceImageCrop(size: try ReferencePixelSize(width: 9, height: 1))
        XCTAssertThrowsError(try ReferenceCompositionLayout(front: huge, side: nil))
        XCTAssertThrowsError(try ReferenceCompositionLayout(front: nil, side: huge))
        XCTAssertThrowsError(try ReferenceCompositionLayout(front: nil, side: nil))
    }
}
