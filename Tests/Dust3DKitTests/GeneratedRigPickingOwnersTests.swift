import XCTest

@testable import Dust3DKit

final class GeneratedRigPickingOwnersTests: XCTestCase {
    private func vertex(_ index: Int) -> RigTemplateMeshVertex {
        RigTemplateMeshVertex(position: .zero, normal: SIMD3(0, 0, 1), boneIndex: index, role: .bone)
    }
    func testTriangleOwnersRetainOriginalIndicesAfterZeroAxisJointsAreOmitted() throws {
        let skeleton = GeneratedRigSkeleton(
            vertices: [vertex(2), vertex(2), vertex(2)], boneNames: ["Zero", "Other", "Tail"])
        XCTAssertEqual(try skeleton.triangleOwners(), [2])
        XCTAssertEqual(try GeneratedRigSkeleton(vertices: [], boneNames: ["Root"]).triangleOwners(), [])
    }
    func testMixedOrOutOfRangeOwnersAndPartialTrianglesRejectCopiedMetadata() {
        for vertices in [
            [vertex(0), vertex(1), vertex(0)], [vertex(-1), vertex(-1), vertex(-1)], [vertex(2), vertex(2), vertex(2)],
            [vertex(0)],
        ] {
            XCTAssertThrowsError(
                try GeneratedRigSkeleton(vertices: vertices, boneNames: ["Root", "Child"]).triangleOwners())
        }
    }
}
