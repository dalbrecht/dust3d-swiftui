import Dust3DEditorModel
import XCTest

final class ReferenceCropAdjustmentTests: XCTestCase {
    func testResizingRetainsTheInitialHandleGrabOffsetAndSmallCropsCanMove() throws {
        let size = try ReferencePixelSize(width: 100, height: 100)
        let projection = try ReferenceCropProjection(size: size, width: 400, height: 400)
        let crop = try ReferenceImageCrop(size: size, x: 20, y: 20, width: 60, height: 60)
        XCTAssertEqual(
            try projection.adjust(
                crop, interaction: .resize(.left), from: .init(x: 72, y: 200), to: .init(x: 112, y: 200)),
            try ReferenceImageCrop(size: size, x: 30, y: 20, width: 50, height: 60))
        let small = try ReferenceImageCrop(size: size, x: 20, y: 20, width: 4, height: 4)
        XCTAssertEqual(try projection.interaction(at: .init(x: 88, y: 88), crop: small, isAdjusting: true), .move)
        XCTAssertEqual(
            try projection.adjust(
                crop, interaction: .resize(.left), from: .init(x: 72, y: 200),
                to: .init(x: -Double.greatestFiniteMagnitude, y: 200)),
            try ReferenceImageCrop(size: size, x: 0, y: 20, width: 80, height: 60))
    }

    func testMovePreservesExtentAndClampsToTheImageWithoutOverflow() throws {
        let size = try ReferencePixelSize(width: 100, height: 50)
        let projection = try ReferenceCropProjection(size: size, width: 200, height: 200)
        let crop = try ReferenceImageCrop(size: size, x: 20, y: 10, width: 40, height: 20)
        XCTAssertEqual(
            try projection.adjust(crop, interaction: .move, from: .init(x: 80, y: 90), to: .init(x: 100, y: 100)),
            try ReferenceImageCrop(size: size, x: 30, y: 15, width: 40, height: 20))
        XCTAssertEqual(
            try projection.adjust(crop, interaction: .move, from: .init(x: 80, y: 90), to: .init(x: 1e300, y: 1e300)),
            try ReferenceImageCrop(size: size, x: 60, y: 30, width: 40, height: 20))
        XCTAssertEqual(
            try projection.adjust(crop, interaction: .move, from: .init(x: 80, y: 90), to: .init(x: -1e300, y: -1e300)),
            try ReferenceImageCrop(size: size, x: 0, y: 0, width: 40, height: 20))
    }

    func testEveryResizeHandleKeepsItsOppositeBoundaryAndAtLeastOnePixel() throws {
        let size = try ReferencePixelSize(width: 100, height: 50)
        let projection = try ReferenceCropProjection(size: size, width: 200, height: 200)
        let crop = try ReferenceImageCrop(size: size, x: 20, y: 10, width: 40, height: 20)
        let expected: [ReferenceCropHandle: [Int]] = [
            .topLeft: [59, 29, 1, 1], .top: [20, 29, 40, 1], .topRight: [20, 29, 50, 1],
            .right: [20, 10, 50, 20], .bottomRight: [20, 10, 50, 30], .bottom: [20, 10, 40, 30],
            .bottomLeft: [59, 10, 1, 30], .left: [59, 10, 1, 20],
        ]
        for handle in ReferenceCropHandle.allCases {
            let value = try XCTUnwrap(expected[handle])
            XCTAssertEqual(
                try projection.adjust(
                    crop, interaction: .resize(handle), from: projection.handlePoint(handle, crop: crop),
                    to: .init(x: 140, y: 130)),
                try ReferenceImageCrop(size: size, x: value[0], y: value[1], width: value[2], height: value[3]),
                "Resize \(handle) must preserve its stationary edges")
        }
        XCTAssertEqual(
            try projection.adjust(
                crop, interaction: .resize(.topLeft), from: .init(x: 40, y: 70), to: .init(x: -1e300, y: -1e300)),
            try ReferenceImageCrop(size: size, x: 0, y: 0, width: 60, height: 30))
    }

    func testAdjustHitTestingDistinguishesHandlesInteriorAndNewSelections() throws {
        let size = try ReferencePixelSize(width: 100, height: 100)
        let projection = try ReferenceCropProjection(size: size, width: 400, height: 400)
        let crop = try ReferenceImageCrop(size: size, x: 20, y: 20, width: 60, height: 60)
        for handle in ReferenceCropHandle.allCases {
            let point = try projection.handlePoint(handle, crop: crop)
            XCTAssertEqual(try projection.interaction(at: point, crop: crop, isAdjusting: true), .resize(handle))
        }
        XCTAssertEqual(try projection.interaction(at: .init(x: 200, y: 200), crop: crop, isAdjusting: true), .move)
        XCTAssertEqual(try projection.interaction(at: .init(x: 0, y: 0), crop: crop, isAdjusting: true), .draw)
        XCTAssertEqual(try projection.interaction(at: .init(x: 200, y: 200), crop: crop, isAdjusting: false), .draw)
        XCTAssertEqual(
            try projection.adjust(crop, interaction: .draw, from: .init(x: 40, y: 40), to: .init(x: 120, y: 120)),
            try ReferenceImageCrop(size: size, x: 10, y: 10, width: 20, height: 20))
    }

    func testInvalidCoordinatesAndMismatchedSourceCannotAlterACrop() throws {
        let size = try ReferencePixelSize(width: 100, height: 50)
        let projection = try ReferenceCropProjection(size: size, width: 200, height: 200)
        let crop = ReferenceImageCrop(size: size)
        for point in [CanvasPoint(x: .nan, y: 0), .init(x: 0, y: .infinity)] {
            XCTAssertThrowsError(try projection.interaction(at: point, crop: crop, isAdjusting: true))
            XCTAssertThrowsError(try projection.adjust(crop, interaction: .move, from: point, to: .init(x: 1, y: 1)))
            XCTAssertThrowsError(
                try projection.adjust(crop, interaction: .resize(.left), from: .init(x: 1, y: 1), to: point))
        }
        let other = ReferenceImageCrop(size: try .init(width: 50, height: 50))
        XCTAssertThrowsError(try projection.handlePoint(.left, crop: other))
        XCTAssertThrowsError(try projection.interaction(at: .init(x: 1, y: 1), crop: other, isAdjusting: true))
        XCTAssertThrowsError(
            try projection.adjust(other, interaction: .move, from: .init(x: 1, y: 1), to: .init(x: 2, y: 2)))
    }
}
