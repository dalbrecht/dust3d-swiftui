import XCTest

@testable import Dust3DKit

@MainActor
final class GeneratedRigPreviewMeshTests: XCTestCase {
    func testSkeletonPrecedesGroundedBodyWithoutIndependentNormalization() throws {
        let rig = fixture()
        let skeleton = GeneratedRigSkeleton(
            vertices: [0, 1, 2].map { _ in
                RigTemplateMeshVertex(position: SIMD3(12, 3, 4), normal: SIMD3(0, 1, 0), boneIndex: 0, role: .bone)
            }, boneNames: ["Root"])
        let mesh = try rig.previewMesh(
            skeleton: skeleton, boneColor: SIMD4(1, 0, 0, 0.2),
            selectedBoneColor: .one, ringColor: .one)
        XCTAssertEqual(mesh.vertices.count, 6)
        XCTAssertEqual(mesh.vertices[0].position, SIMD3(12, 3, 4))
        XCTAssertEqual(mesh.vertices[0].color, SIMD4(1, 0, 0, 1))
        XCTAssertEqual(mesh.vertices[3].position, rig.mesh.vertices[0].position)
        XCTAssertEqual(mesh.vertices[3].normal, rig.mesh.vertices[0].normal)
        XCTAssertEqual(mesh.vertices[3].color, SIMD4(0.5, 0.5, 0.5, 0.8))
        XCTAssertEqual(mesh.nodeCount, 2)
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertEqual(mesh.warning, "retained warning")
    }

    func testZeroAxisSkeletonCanBeAbsentAndSourceNamesMustMatchExactly() throws {
        let rig = fixture()
        XCTAssertEqual(
            try rig.previewMesh(
                skeleton: nil, boneColor: .one,
                selectedBoneColor: .one, ringColor: .one
            ).vertices.count, 3)
        let mismatch = GeneratedRigSkeleton(vertices: [], boneNames: ["root"])
        XCTAssertThrowsError(
            try rig.previewMesh(
                skeleton: mismatch, boneColor: .one,
                selectedBoneColor: .one, ringColor: .one))
        XCTAssertThrowsError(
            try rig.previewMesh(
                skeleton: nil, boneColor: SIMD4(.nan, 1, 1, 1),
                selectedBoneColor: .one, ringColor: .one))
    }

    func testSelectedWeightUsesAllFourSlotsAndUnweightedBodyIsGray() throws {
        let base = fixture()
        let rig = GeneratedRig(
            mesh: base.mesh, joints: base.joints,
            influences: [
                GeneratedRigInfluences(joints: .zero, weights: SIMD4(0.1, 0.2, 0.3, 0.4)),
                GeneratedRigInfluences(joints: .init(repeating: .max), weights: .zero),
                GeneratedRigInfluences(joints: SIMD4(.max, .max, .max, 0), weights: SIMD4(0, 0, 0, 0.25)),
            ],
            eyelidsGenerated: false)
        let mesh = try rig.previewMesh(
            skeleton: nil, selectedBoneName: "Root", boneColor: .one,
            selectedBoneColor: .one, ringColor: .one)
        XCTAssertEqual(mesh.vertices[0].color, SIMD4(1, 0, 0, 0.8))
        XCTAssertEqual(mesh.vertices[1].color, SIMD4(0.5, 0.5, 0.5, 0.8))
        XCTAssertEqual(mesh.vertices[2].color, SIMD4(0.25, 0, 0.75, 0.8))
    }

    func testMissingDrawableSkeletonAndMalformedCorrespondenceAreRejected() throws {
        let base = fixture()
        let joint = GeneratedRigJoint(
            name: "Root", parentIndex: nil, head: .zero, tail: SIMD3(0, 1, 0),
            capsuleRadius: 0, closingAngle: 0, restWorld: [], inverseBind: [])
        let rig = GeneratedRig(mesh: base.mesh, joints: [joint], influences: base.influences, eyelidsGenerated: false)
        XCTAssertThrowsError(
            try rig.previewMesh(
                skeleton: nil, boneColor: .one,
                selectedBoneColor: .one, ringColor: .one))
        for (count, boneIndex, position) in [(1, 0, SIMD3<Float>.zero), (3, 1, .zero), (3, 0, SIMD3(.nan, 0, 0))] {
            let skeleton = GeneratedRigSkeleton(
                vertices: Array(
                    repeating:
                        RigTemplateMeshVertex(
                            position: position, normal: SIMD3(0, 1, 0), boneIndex: boneIndex, role: .ring),
                    count: count), boneNames: ["Root"])
            XCTAssertThrowsError(
                try rig.previewMesh(
                    skeleton: skeleton, boneColor: .one,
                    selectedBoneColor: .one, ringColor: .one))
        }
        let invalid = GeneratedRig(mesh: base.mesh, joints: base.joints, influences: [], eyelidsGenerated: false)
        XCTAssertThrowsError(
            try invalid.previewMesh(
                skeleton: nil, boneColor: .one,
                selectedBoneColor: .one, ringColor: .one))
    }

    func testAllSkeletonRolesUsePaletteAndForceOpaqueAlpha() throws {
        let skeleton = GeneratedRigSkeleton(
            vertices: [RigTemplateMeshRole.bone, .selectedBone, .ring].map {
                RigTemplateMeshVertex(position: .zero, normal: SIMD3(0, 1, 0), boneIndex: 0, role: $0)
            }, boneNames: ["Root"])
        let mesh = try fixture().previewMesh(
            skeleton: skeleton, boneColor: SIMD4(1, 0, 0, 0),
            selectedBoneColor: SIMD4(0, 1, 0, 0), ringColor: SIMD4(0, 0, 1, 0))
        XCTAssertEqual(mesh.vertices.prefix(3).map(\.color), [SIMD4(1, 0, 0, 1), SIMD4(0, 1, 0, 1), SIMD4(0, 0, 1, 1)])
    }

    func testCancelledAssemblyDoesNotPublishPartialMesh() async {
        let rig = fixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try rig.previewMesh(skeleton: nil, boneColor: .one, selectedBoneColor: .one, ringColor: .one)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled assembly returned a mesh")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    private func fixture() -> GeneratedRig {
        let vertex = MeshVertex(position: SIMD3(10, 2, 3), normal: SIMD3(0, 0, 1), color: SIMD4(0.2, 0.4, 0.6, 1))
        return GeneratedRig(
            mesh: Mesh(
                vertices: [vertex, vertex, vertex], nodeCount: 2, partCount: 1,
                warning: "retained warning"),
            joints: [
                GeneratedRigJoint(
                    name: "Root", parentIndex: nil,
                    head: .zero, tail: .zero, capsuleRadius: 0, closingAngle: 0, restWorld: [], inverseBind: [])
            ],
            influences: Array(
                repeating: GeneratedRigInfluences(joints: .init(repeating: .max), weights: .zero), count: 3),
            eyelidsGenerated: false)
    }
}
