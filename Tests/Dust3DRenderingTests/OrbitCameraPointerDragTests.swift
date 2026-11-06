import XCTest
import simd

@testable import Dust3DRendering

final class OrbitCameraPointerDragTests: XCTestCase {
    private func projectedCenter(_ camera: OrbitCamera, viewport: SIMD2<Float>) -> SIMD2<Float> {
        let clip = camera.transform(aspect: viewport.x / viewport.y) * SIMD4<Float>(0, 0, 0, 1)
        return SIMD2(clip.x / clip.w, clip.y / clip.w)
    }

    func testOrdinaryYUpDragRetainsExistingOrbitSemantics() {
        var actual = OrbitCamera()
        var expected = actual
        expected.orbit(horizontal: 25, vertical: -10)
        XCTAssertTrue(actual.drag(by: SIMD2(25, 10), viewport: .zero, pans: false))
        XCTAssertEqual(actual.transform(aspect: 1), expected.transform(aspect: 1))
        XCTAssertEqual(actual.distance, expected.distance)
    }

    func testPanMovesWithPointerInViewPointsWithoutChangingOrbitOrZoom() {
        let viewport = SIMD2<Float>(200, 100)
        var camera = OrbitCamera(yaw: 0.7, pitch: -0.4, distance: 5)
        XCTAssertTrue(camera.drag(by: SIMD2(20, 10), viewport: viewport, pans: true))
        let center = projectedCenter(camera, viewport: viewport)
        XCTAssertEqual(center.x, 0.2, accuracy: 0.000001)
        XCTAssertEqual(center.y, 0.2, accuracy: 0.000001)
        XCTAssertEqual(center.x * viewport.x / 2, 20, accuracy: 0.00001)
        XCTAssertEqual(center.y * viewport.y / 2, 10, accuracy: 0.00001)
        XCTAssertEqual(camera.yaw, 0.7)
        XCTAssertEqual(camera.pitch, -0.4)
        XCTAssertEqual(camera.distance, 5)
        XCTAssertTrue(camera.drag(by: SIMD2(-20, -10), viewport: viewport, pans: true))
        XCTAssertEqual(projectedCenter(camera, viewport: viewport), .zero)
    }

    func testPanNormalizationUsesEachViewportAxis() {
        for viewport: SIMD2<Float> in [SIMD2(200, 100), SIMD2(400, 100), SIMD2(100, 400)] {
            var camera = OrbitCamera()
            XCTAssertTrue(camera.drag(by: SIMD2(10, -5), viewport: viewport, pans: true))
            let center = projectedCenter(camera, viewport: viewport)
            XCTAssertEqual(center.x * viewport.x / 2, 10, accuracy: 0.00001)
            XCTAssertEqual(center.y * viewport.y / 2, -5, accuracy: 0.00001)
        }
    }

    func testPanKeepsExistingBoundsEvenWhenFiniteNormalizationExceedsFloatRange() {
        var camera = OrbitCamera()
        camera.pan(horizontal: -1.5, vertical: 1.5)
        XCTAssertTrue(
            camera.drag(
                by: SIMD2(.greatestFiniteMagnitude, -.greatestFiniteMagnitude),
                viewport: SIMD2(repeating: .leastNonzeroMagnitude), pans: true))
        let center = projectedCenter(camera, viewport: SIMD2(100, 100))
        XCTAssertEqual(center.x, 1.5, accuracy: 0.000001)
        XCTAssertEqual(center.y, -1.5, accuracy: 0.000001)
        XCTAssertTrue(camera.yaw.isFinite)
        XCTAssertTrue(camera.pitch.isFinite)
        XCTAssertTrue(camera.distance.isFinite)
    }

    func testInvalidPointerOrPanDimensionsDoNotChangeCamera() {
        for pans in [false, true] {
            var camera = OrbitCamera()
            camera.pan(horizontal: 0.3, vertical: -0.2)
            let original = camera.transform(aspect: 1)
            for delta: SIMD2<Float> in [SIMD2(.nan, 1), SIMD2(1, .infinity), SIMD2(-.infinity, 1)] {
                XCTAssertFalse(camera.drag(by: delta, viewport: SIMD2(200, 100), pans: pans))
                XCTAssertEqual(camera.transform(aspect: 1), original)
            }
        }
        var camera = OrbitCamera()
        let original = camera.transform(aspect: 1)
        for viewport: SIMD2<Float> in [.zero, SIMD2(-1, 100), SIMD2(100, .nan), SIMD2(.infinity, 100)] {
            XCTAssertFalse(camera.drag(by: SIMD2(1, 1), viewport: viewport, pans: true))
            XCTAssertEqual(camera.transform(aspect: 1), original)
        }
    }

    func testZeroDragIsAcceptedWithoutMovingEitherMode() {
        for pans in [false, true] {
            var camera = OrbitCamera()
            let original = camera.transform(aspect: 1)
            XCTAssertTrue(camera.drag(by: .zero, viewport: SIMD2(200, 100), pans: pans))
            XCTAssertEqual(camera.transform(aspect: 1), original)
        }
    }
}
