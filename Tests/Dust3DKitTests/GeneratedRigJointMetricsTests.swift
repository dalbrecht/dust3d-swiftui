import XCTest

@testable import Dust3DKit

final class GeneratedRigJointMetricsTests: XCTestCase {
    private func joint(head: SIMD3<Float> = .zero, tail: SIMD3<Float> = .zero, angle: Float = 0) -> GeneratedRigJoint {
        GeneratedRigJoint(
            name: "Joint", parentIndex: nil, head: head, tail: tail, capsuleRadius: 0.1,
            closingAngle: angle, restWorld: [], inverseBind: [])
    }

    func testLengthUsesTheGroundedEndpointDifferenceInModelUnits() {
        XCTAssertEqual(joint(head: SIMD3(10, 2, -5), tail: SIMD3(13, 6, 7)).lengthInModelUnits, 13)
        XCTAssertEqual(joint(head: .one, tail: .one).lengthInModelUnits, 0)
    }

    func testLengthConvertsBeforeSubtractingLargeFiniteFloatCoordinates() {
        let limit = Float.greatestFiniteMagnitude
        let value = joint(head: SIMD3(-limit, 0, 0), tail: SIMD3(limit, 0, 0)).lengthInModelUnits
        XCTAssertTrue(value.isFinite)
        XCTAssertEqual(value, Double(limit) * 2)
    }

    func testClosingAngleConvertsSignedRadiansToDegrees() {
        for (radians, degrees): (Float, Double) in [(0, 0), (.pi / 2, 90), (-.pi / 3, -60), (.pi, 180)] {
            XCTAssertEqual(joint(angle: radians).closingAngleDegrees, degrees, accuracy: 0.00002)
        }
    }
}
