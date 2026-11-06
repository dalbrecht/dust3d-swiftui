import XCTest

@testable import Dust3DKit

final class GeneratedRigValueTests: XCTestCase {
    func testFourInfluencesDistinguishUnboundAndAnyPositiveSlot() {
        XCTAssertFalse(GeneratedRigInfluences(joints: .init(repeating: .max), weights: .zero).isBound)
        for slot in 0..<4 {
            var weights = SIMD4<Float>.zero
            weights[slot] = 1
            XCTAssertTrue(GeneratedRigInfluences(joints: .zero, weights: weights).isBound)
        }
    }
}
