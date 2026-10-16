import Dust3DEditorModel
import XCTest

final class ReferenceCropProjectionTests: XCTestCase {
    func testLetterboxedPointerSelectionMapsClampsAndNormalizesPixelBoundaries() throws {
        let size = try ReferencePixelSize(width: 100, height: 50)
        let projection = try ReferenceCropProjection(size: size, width: 200, height: 200)
        XCTAssertEqual(projection.imageX, 0)
        XCTAssertEqual(projection.imageY, 50)
        XCTAssertEqual(projection.imageWidth, 200)
        XCTAssertEqual(projection.imageHeight, 100)
        XCTAssertEqual(
            try projection.crop(from: .init(x: 180, y: 140), to: .init(x: 20, y: 60)),
            try ReferenceImageCrop(size: size, x: 10, y: 5, width: 80, height: 40))
        XCTAssertEqual(
            try projection.crop(from: .init(x: -1e300, y: -1e300), to: .init(x: 1e300, y: 1e300)), .init(size: size))
        let portrait = try ReferenceCropProjection(size: size, width: 200, height: 50)
        XCTAssertEqual(portrait.imageX, 50)
        XCTAssertEqual(portrait.imageY, 0)
        XCTAssertThrowsError(try projection.crop(from: .init(x: 0, y: 0), to: .init(x: 0, y: 0)))
        XCTAssertThrowsError(try projection.crop(from: .init(x: .nan, y: 0), to: .init(x: 20, y: 20)))
        for value in [0.0, -1, .infinity, .nan, 1e9] {
            XCTAssertThrowsError(try ReferenceCropProjection(size: size, width: value, height: 100))
            XCTAssertThrowsError(try ReferenceCropProjection(size: size, width: 100, height: value))
        }
    }
}
