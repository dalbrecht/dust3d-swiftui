import XCTest

@testable import Dust3DEditorModel

final class EndpointIKTests: XCTestCase {
    func testSingleSegmentMovesTowardReachableAndUnreachableTargetsWithoutChangingLength() throws {
        let root = SIMD3<Double>(0, 0, 0)
        let end = SIMD3<Double>(1, 0, 0)
        for target in [SIMD3<Double>(0, 1, 0), SIMD3<Double>(0, 5, 0), SIMD3<Double>(-1, 0, 0)] {
            let result = try EndpointIK.solve([root, end], toward: target)
            XCTAssertEqual(result[0], root)
            XCTAssertEqual(result[1].x, target.x, accuracy: 1e-12)
            XCTAssertEqual(result[1].y, target.y == 0 ? 0 : 1, accuracy: 1e-12)
            XCTAssertEqual(result[1].z, 0, accuracy: 1e-12)
        }
    }

    func testBentChainPreservesEveryLengthAndImprovesDistanceInThreeDimensions() throws {
        let chain: [SIMD3<Double>] = [.zero, [1, 0, 0], [1, 1, 0], [1, 1, 1]]
        let target = SIMD3<Double>(0, 1.5, 1.5)
        let result = try EndpointIK.solve(chain, toward: target)
        func distanceSquared(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
            let d = a - b
            return d.x * d.x + d.y * d.y + d.z * d.z
        }
        XCTAssertEqual(result[0], chain[0])
        XCTAssertLessThan(distanceSquared(result[3], target), 0.002)
        for i in 1..<chain.count {
            XCTAssertEqual(
                distanceSquared(result[i], result[i - 1]),
                distanceSquared(chain[i], chain[i - 1]), accuracy: 1e-12)
        }
    }

    func testCoincidentNodesAndAnAlreadyReachedTargetRemainFiniteAndStable() throws {
        let chain: [SIMD3<Double>] = [.zero, .zero, [1, 0, 0]]
        XCTAssertEqual(try EndpointIK.solve(chain, toward: chain[2]), chain)
        let moved = try EndpointIK.solve(chain, toward: [0, 1, 0])
        XCTAssertEqual(moved[0], .zero)
        XCTAssertEqual(moved[1], .zero)
        XCTAssertEqual(moved[2].y, 1, accuracy: 1e-12)
        XCTAssertEqual(try EndpointIK.solve([.zero], toward: [0, 1, 0]), [.zero])
    }
}
