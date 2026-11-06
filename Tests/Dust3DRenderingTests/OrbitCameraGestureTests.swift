import XCTest
import simd

@testable import Dust3DRendering

final class OrbitCameraGestureTests: XCTestCase {
    func testMagnificationUsesIncrementalScaleAndComplementaryPinchesRestoreDistance() {
        var camera = OrbitCamera()
        XCTAssertTrue(camera.magnify(by: 0.25))
        XCTAssertEqual(camera.distance, 3 / 1.25, accuracy: 0.000001)
        XCTAssertTrue(camera.magnify(by: -0.2))
        XCTAssertEqual(camera.distance, 3, accuracy: 0.000001)
        XCTAssertTrue(camera.magnify(by: 0))
        XCTAssertEqual(camera.distance, 3, accuracy: 0.000001)
        XCTAssertTrue(camera.magnify(by: 0.1))
        XCTAssertTrue(camera.magnify(by: 0.1))
        XCTAssertEqual(camera.distance, 3 / (1.1 * 1.1), accuracy: 0.000001)
    }

    func testMagnificationRetainsExistingZoomLimitsForExtremeFiniteDeltas() {
        var close = OrbitCamera()
        XCTAssertTrue(close.magnify(by: Double.greatestFiniteMagnitude))
        XCTAssertEqual(close.distance, 1.25)
        var far = OrbitCamera()
        XCTAssertTrue(far.magnify(by: (-1.0).nextUp))
        XCTAssertEqual(far.distance, 20)
        var half = OrbitCamera()
        XCTAssertTrue(half.magnify(by: 1))
        XCTAssertEqual(half.distance, 1.5, accuracy: 0.000001)
    }

    func testInvalidMagnificationLeavesAllCameraStateUnchanged() {
        var camera = OrbitCamera(yaw: 0.7, pitch: -0.4, distance: 5)
        camera.pan(horizontal: 0.3, vertical: -0.2)
        let original = camera.transform(aspect: 1.7)
        for value: Double in [-1, -2, -.infinity, .infinity, .nan] {
            XCTAssertFalse(camera.magnify(by: value))
            XCTAssertEqual(camera.transform(aspect: 1.7), original)
        }
    }

    func testPositiveCounterclockwiseRotationTurnsLeftInDegrees() {
        var camera = OrbitCamera(yaw: 0, pitch: 0.3, distance: 5)
        camera.pan(horizontal: 0.2, vertical: -0.1)
        var expected = camera
        expected.orbit(horizontal: -Float.pi / 2 / 0.01, vertical: 0)
        XCTAssertTrue(camera.rotateGesture(by: 90))
        XCTAssertEqual(camera.yaw, -Float.pi / 2, accuracy: 0.000001)
        XCTAssertEqual(camera.pitch, 0.3)
        XCTAssertEqual(camera.distance, 5)
        let actualTransform = camera.transform(aspect: 1)
        let expectedTransform = expected.transform(aspect: 1)
        for column in 0..<4 {
            for row in 0..<4 {
                XCTAssertEqual(actualTransform[column][row], expectedTransform[column][row], accuracy: 0.000001)
            }
        }
        XCTAssertTrue(camera.rotateGesture(by: -90))
        XCTAssertEqual(camera.yaw, 0, accuracy: 0.000001)
    }

    func testRotationMatchesExistingDiscreteOrbitDirections() {
        let menuDegrees = 18.0 * 0.01 * 180 / Double.pi
        for (degrees, horizontal): (Double, Float) in [(menuDegrees, -18), (-menuDegrees, 18)] {
            var menu = OrbitCamera()
            menu.orbit(horizontal: horizontal, vertical: 0)
            var gesture = OrbitCamera()
            XCTAssertTrue(gesture.rotateGesture(by: degrees))
            XCTAssertEqual(gesture.yaw, menu.yaw, accuracy: 0.000001)
            XCTAssertEqual(gesture.pitch, menu.pitch)
            XCTAssertEqual(gesture.distance, menu.distance)
        }
    }

    func testFullTurnsAndExtremeFiniteRotationRemainBounded() {
        var camera = OrbitCamera()
        let original = camera.transform(aspect: 1)
        XCTAssertTrue(camera.rotateGesture(by: 0))
        XCTAssertTrue(camera.rotateGesture(by: 360))
        XCTAssertTrue(camera.rotateGesture(by: -720))
        XCTAssertEqual(camera.transform(aspect: 1), original)
        var wrapped = OrbitCamera(yaw: 0)
        XCTAssertTrue(wrapped.rotateGesture(by: 540))
        XCTAssertEqual(wrapped.yaw, -Float.pi, accuracy: 0.000001)
        XCTAssertTrue(camera.rotateGesture(by: Double.greatestFiniteMagnitude))
        XCTAssertTrue(camera.yaw.isFinite)
        XCTAssertLessThan(abs(camera.yaw + 0.35), 2 * .pi + 0.000001)
    }

    func testInvalidRotationLeavesAllCameraStateUnchanged() {
        var camera = OrbitCamera(yaw: 0.7, pitch: -0.4, distance: 5)
        camera.pan(horizontal: 0.3, vertical: -0.2)
        let original = camera.transform(aspect: 1.7)
        for value: Double in [-.infinity, .infinity, .nan] {
            XCTAssertFalse(camera.rotateGesture(by: value))
            XCTAssertEqual(camera.transform(aspect: 1.7), original)
        }
    }
}
