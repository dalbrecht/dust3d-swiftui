import XCTest

@testable import Dust3DKit

@MainActor
final class GeneratedRigWeightSummaryTests: XCTestCase {
    private func influence(_ indices: SIMD4<UInt32>, _ weights: SIMD4<Float>) -> GeneratedRigInfluences {
        GeneratedRigInfluences(joints: indices, weights: weights)
    }

    private var unbound: GeneratedRigInfluences {
        influence(.init(repeating: .max), .zero)
    }

    private func rig(_ influences: [GeneratedRigInfluences], corners: Int? = nil) -> GeneratedRig {
        let vertex = MeshVertex(position: .zero, normal: SIMD3(0, 0, 1), color: .one)
        let joints = ["é", "e\u{301}", "Other"].map { name in
            GeneratedRigJoint(
                name: name, parentIndex: nil, head: .zero, tail: .zero,
                capsuleRadius: 0, closingAngle: 0, restWorld: [], inverseBind: [])
        }
        return GeneratedRig(
            mesh: Mesh(
                vertices: Array(repeating: vertex, count: corners ?? influences.count),
                nodeCount: 2, partCount: 1, warning: ""),
            joints: joints, influences: influences, eyelidsGenerated: false)
    }

    func testSumsEverySelectedSlotAndCountsTrianglesRatherThanPositiveCorners() throws {
        let value = rig([
            influence(.zero, SIMD4(0.1, 0.2, 0.3, 0.4)),
            influence(SIMD4(2, .max, .max, 0), SIMD4(0.75, 0, 0, 0.25)),
            influence(SIMD4(2, 0, 0, .max), SIMD4(0.5, 0.2, 0.3, 0)),
            influence(SIMD4(2, .max, .max, .max), SIMD4(1, 0, 0, 0)),
            unbound, unbound,
        ])
        let summary = try XCTUnwrap(value.weightSummary(selectedBoneName: "é"))
        XCTAssertEqual(summary.minimumWeight, 0)
        XCTAssertEqual(summary.maximumWeight, 1, accuracy: 0.00001)
        XCTAssertEqual(summary.influencedTriangleCount, 1)
        XCTAssertEqual(summary.triangleCount, 2)
        XCTAssertEqual(
            summary,
            GeneratedRigWeightSummary(minimumWeight: 0, maximumWeight: summary.maximumWeight, influencedTriangleCount: 1, triangleCount: 2))
    }

    func testExactUTF8NamesRemainDistinctAndUnselectedKnownBoneHasZeroRange() throws {
        let value = rig([
            influence(SIMD4(0, 1, .max, .max), SIMD4(0.75, 0.25, 0, 0)), unbound, unbound,
        ])
        XCTAssertEqual(try value.weightSummary(selectedBoneName: "é")?.maximumWeight, 0.75)
        XCTAssertEqual(try value.weightSummary(selectedBoneName: "e\u{301}")?.maximumWeight, 0.25)
        XCTAssertEqual(
            try value.weightSummary(selectedBoneName: "Other"),
            GeneratedRigWeightSummary(minimumWeight: 0, maximumWeight: 0, influencedTriangleCount: 0, triangleCount: 1))
        XCTAssertNil(try value.weightSummary(selectedBoneName: ""))
        XCTAssertNil(try value.weightSummary(selectedBoneName: "Missing"))
    }

    func testMinimumIncludesEveryBodyCorner() throws {
        let value = rig([
            influence(SIMD4(0, 2, .max, .max), SIMD4(0.1, 0.9, 0, 0)),
            influence(SIMD4(0, 2, .max, .max), SIMD4(0.5, 0.5, 0, 0)),
            influence(SIMD4(0, .max, .max, .max), SIMD4(1, 0, 0, 0)),
        ])
        let summary = try XCTUnwrap(value.weightSummary(selectedBoneName: "é"))
        XCTAssertEqual(summary.minimumWeight, 0.1, accuracy: 0.000001)
        XCTAssertEqual(summary.maximumWeight, 1)
        XCTAssertEqual(summary.influencedTriangleCount, 1)
    }

    func testPreservesNativeNormalizationToleranceWithoutClamping() throws {
        let secondWeights: [Float] = [0.49995, 0.50005]
        for second in secondWeights {
            let record = influence(SIMD4(0, 0, .max, .max), SIMD4(0.5, second, 0, 0))
            let summary = try XCTUnwrap(rig(Array(repeating: record, count: 3)).weightSummary(selectedBoneName: "é"))
            let expected: Float = 0.5 + second
            XCTAssertEqual(summary.minimumWeight, expected, accuracy: 0.000001)
            XCTAssertEqual(summary.maximumWeight, expected, accuracy: 0.000001)
            XCTAssertEqual(summary.influencedTriangleCount, 1)
        }
    }

    func testAnyPositiveCornerCountsWithoutAnEpsilonCutoff() throws {
        let record = influence(SIMD4(0, 2, .max, .max), SIMD4(Float.leastNonzeroMagnitude, 1, 0, 0))
        let summary = try XCTUnwrap(rig([unbound, record, unbound]).weightSummary(selectedBoneName: "é"))
        XCTAssertEqual(summary.minimumWeight, 0)
        XCTAssertEqual(summary.maximumWeight, Float.leastNonzeroMagnitude)
        XCTAssertEqual(summary.influencedTriangleCount, 1)
    }

    func testRejectsEmptyNonTriangleAndMismatchedBodyCorrespondence() {
        for value in [rig([], corners: 0), rig([unbound], corners: 1), rig([unbound, unbound], corners: 3)] {
            XCTAssertThrowsError(try value.weightSummary(selectedBoneName: "é")) {
                XCTAssertTrue($0 is GeneratedRigWeightSummaryError)
                XCTAssertFalse($0.localizedDescription.isEmpty)
            }
        }
    }

    func testRejectsNonfiniteRangeAndInvalidJointSlots() {
        let invalid = [
            influence(SIMD4(0, .max, .max, .max), SIMD4(.nan, 0, 0, 0)),
            influence(SIMD4(0, .max, .max, .max), SIMD4(.infinity, 0, 0, 0)),
            influence(SIMD4(0, .max, .max, .max), SIMD4(-0.1, 0, 0, 0)),
            influence(SIMD4(0, .max, .max, .max), SIMD4(1.1, 0, 0, 0)),
            influence(.init(repeating: .max), SIMD4(0.5, 0, 0, 0)),
            influence(SIMD4(99, .max, .max, .max), SIMD4(0.5, 0, 0, 0)),
            influence(SIMD4(0, .max, .max, .max), .zero),
            influence(SIMD4(0, 2, .max, .max), SIMD4(0.5, .nan, 0, 0)),
            influence(SIMD4(0, 0, .max, .max), SIMD4(0.75, 0.75, 0, 0)),
            influence(SIMD4(0, .max, .max, .max), SIMD4(0.5, 0, 0, 0)),
            influence(SIMD4(0, 0, .max, .max), SIMD4(0.5, 0.5002, 0, 0)),
            influence(SIMD4(0, 0, .max, .max), SIMD4(0.5, 0.4998, 0, 0)),
        ]
        for value in invalid {
            XCTAssertThrowsError(try rig([value, unbound, unbound]).weightSummary(selectedBoneName: "é")) {
                XCTAssertTrue($0 is GeneratedRigWeightSummaryError)
                XCTAssertFalse($0.localizedDescription.isEmpty)
            }
        }
    }

    func testPrecancelledNoneSelectionThrowsBeforeReturning() async {
        let value = rig([unbound, unbound, unbound])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try value.weightSummary(selectedBoneName: "")
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
