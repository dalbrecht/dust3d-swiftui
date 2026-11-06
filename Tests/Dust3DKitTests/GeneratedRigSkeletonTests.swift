#if MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Foundation
    import XCTest
    @testable import Dust3DKit

    private func skeletonJoint(_ name: String, head: SIMD3<Float>, tail: SIMD3<Float>) -> GeneratedRigJoint {
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        return GeneratedRigJoint(
            name: name, parentIndex: nil, head: head, tail: tail, capsuleRadius: 0.1, closingAngle: 0,
            restWorld: identity, inverseBind: identity)
    }

    private func skeletonRig(_ joints: [GeneratedRigJoint]) -> GeneratedRig {
        GeneratedRig(
            mesh: Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: ""), joints: joints,
            influences: [], eyelidsGenerated: false)
    }

    @MainActor
    final class GeneratedRigSkeletonTests: XCTestCase {
        func testZeroAxesKeepOriginalNamesIndicesAndUnnormalizedFrame() async throws {
            let result = try await Task.detached {
                let joints = [
                    skeletonJoint("Unplaced", head: .zero, tail: .zero),
                    skeletonJoint("é", head: SIMD3(10, 2, 3), tail: SIMD3(10, 4, 3)),
                    skeletonJoint("Another zero", head: SIMD3(8, 2, 3), tail: SIMD3(8, 2, 3)),
                    skeletonJoint("e\u{301}", head: SIMD3(12, 1, 3), tail: SIMD3(12, 3, 3)),
                ]
                return try skeletonRig(joints).skeletonMesh(selectedBoneName: "é")
            }.value
            let mesh = try XCTUnwrap(result)
            XCTAssertEqual(
                mesh.boneNames.map { Data($0.utf8) },
                ["Unplaced", "é", "Another zero", "e\u{301}"].map { Data($0.utf8) })
            XCTAssertEqual(mesh.vertices.count, 2 * 1764)
            XCTAssertEqual(Set(mesh.vertices.map(\.boneIndex)), [1, 3])
            XCTAssertEqual(Set(mesh.vertices.filter { $0.role == .selectedBone }.map(\.boneIndex)), [1])
            XCTAssertTrue(mesh.vertices.allSatisfy { $0.position.x > 9 })
        }

        func testAllZeroAxesHaveNoGeometryAndTinyNonzeroAxisIsNotFiltered() async throws {
            let result = try await Task.detached {
                let zero = skeletonRig([skeletonJoint("Root", head: .one, tail: .one)])
                let tiny = skeletonRig([skeletonJoint("Tiny", head: .zero, tail: SIMD3(0, 0, 1e-25))])
                return (try zero.skeletonMesh(), try tiny.skeletonMesh())
            }.value
            XCTAssertNil(result.0)
            let tiny = try XCTUnwrap(result.1)
            XCTAssertEqual(tiny.boneNames, ["Tiny"])
            XCTAssertEqual(tiny.vertices.count, 36)
            XCTAssertTrue(tiny.vertices.allSatisfy { $0.boneIndex == 0 })
        }

        func testInvalidSkippedJointAndDuplicateNamesRejectBeforeNativeMath() async throws {
            let rejected = await Task.detached {
                let invalid = skeletonRig([skeletonJoint("Bad", head: SIMD3(.nan, 0, 0), tail: SIMD3(.nan, 0, 0))])
                let duplicate = skeletonRig([
                    skeletonJoint("Same", head: .zero, tail: .zero),
                    skeletonJoint("Same", head: .one, tail: .one),
                ])
                return [invalid, duplicate].map { rig in
                    do {
                        _ = try rig.skeletonMesh()
                        return false
                    } catch is MeshLoadingError { return true } catch { return false }
                }
            }.value
            XCTAssertEqual(rejected, [true, true])
        }

        func testPrecancelledPreparationStopsBeforeNativeMath() async throws {
            let task = Task {
                try skeletonRig([skeletonJoint("Root", head: .zero, tail: SIMD3(0, 1, 0))]).skeletonMesh()
            }
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {}
        }
    }
#endif
