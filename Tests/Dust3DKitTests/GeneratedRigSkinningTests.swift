import XCTest

@testable import Dust3DKit

final class GeneratedRigSkinningTests: XCTestCase {
    private static let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

    private func translation(_ x: Double, _ y: Double = 0) -> [Double] {
        var matrix = Self.identity
        matrix[12] = x
        matrix[13] = y
        return matrix
    }

    private func rig(
        rest: [[Double]], inverse: [[Double]], weights: SIMD4<Float>, indices: SIMD4<UInt32>,
        normal: SIMD3<Float> = SIMD3(2, 0, 0)
    ) -> GeneratedRig {
        let joints = rest.indices.map {
            GeneratedRigJoint(
                name: "Bone \($0)", parentIndex: nil, head: .zero, tail: .zero, capsuleRadius: 0,
                closingAngle: 0, restWorld: rest[$0], inverseBind: inverse[$0])
        }
        let vertex = MeshVertex(position: SIMD3(3, 0, 0), normal: normal, color: SIMD4(0.2, 0.4, 0.6, 0.8))
        return GeneratedRig(
            mesh: Mesh(vertices: Array(repeating: vertex, count: 3), nodeCount: 2, partCount: 1, warning: "Fixture"),
            joints: joints,
            influences: Array(repeating: GeneratedRigInfluences(joints: indices, weights: weights), count: 3),
            eyelidsGenerated: false)
    }

    func testRestIdentityAndRotationAboutTranslatedJointPreserveMetadata() throws {
        let fixture = rig(
            rest: [translation(2)], inverse: [translation(-2)], weights: SIMD4(1, 0, 0, 0),
            indices: SIMD4(0, .max, .max, .max))
        let rest = try fixture.referenceSkinnedMesh(modelFromJoint: fixture.joints.map(\.restWorld))
        XCTAssertEqual(rest.vertices.map(\.position), fixture.mesh.vertices.map(\.position))
        XCTAssertEqual(rest.vertices.map(\.normal), fixture.mesh.vertices.map(\.normal))
        let rotated: [Double] = [0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 2, 0, 0, 1]
        let result = try fixture.referenceSkinnedMesh(modelFromJoint: [rotated])
        XCTAssertEqual(result.vertices.map(\.position), Array(repeating: SIMD3<Float>(2, 1, 0), count: 3))
        XCTAssertEqual(result.vertices.map(\.normal), Array(repeating: SIMD3<Float>(0, 2, 0), count: 3))
        XCTAssertEqual(result.vertices.map(\.color), fixture.mesh.vertices.map(\.color))
        XCTAssertEqual(result.nodeCount, 2)
        XCTAssertEqual(result.partCount, 1)
        XCTAssertEqual(result.warning, "Fixture")
        XCTAssertEqual(fixture.mesh.vertices[0].position, SIMD3(3, 0, 0))
    }

    func testFourJointBlendAndUnboundVertices() throws {
        let fixture = rig(
            rest: Array(repeating: Self.identity, count: 4), inverse: Array(repeating: Self.identity, count: 4),
            weights: SIMD4(0.125, 0.25, 0.125, 0.5), indices: SIMD4(0, 1, 2, 3))
        let result = try fixture.referenceSkinnedMesh(modelFromJoint: [
            translation(2), translation(4), translation(8), translation(16),
        ])
        XCTAssertEqual(result.vertices[0].position, SIMD3(13.25, 0, 0))
        XCTAssertEqual(result.vertices[0].normal, SIMD3(2, 0, 0))
        let unbound = rig(rest: [], inverse: [], weights: .zero, indices: SIMD4(repeating: .max))
        let unchanged = try unbound.referenceSkinnedMesh(modelFromJoint: [])
        XCTAssertEqual(unchanged.vertices.map(\.position), unbound.mesh.vertices.map(\.position))
        XCTAssertEqual(unchanged.vertices.map(\.normal), unbound.mesh.vertices.map(\.normal))
    }

    func testOppositeDirectionBlendKeepsRestNormal() throws {
        let fixture = rig(
            rest: [Self.identity, Self.identity], inverse: [Self.identity, Self.identity],
            weights: SIMD4(0.5, 0.5, 0, 0), indices: SIMD4(0, 1, .max, .max))
        let halfTurn: [Double] = [-1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let result = try fixture.referenceSkinnedMesh(modelFromJoint: [Self.identity, halfTurn])
        XCTAssertEqual(result.vertices[0].position, .zero)
        XCTAssertEqual(result.vertices[0].normal, SIMD3(2, 0, 0))
    }

    func testRejectsMalformedPoseAndInfluenceReceipts() throws {
        let fixture = rig(
            rest: [Self.identity], inverse: [Self.identity], weights: SIMD4(1, 0, 0, 0),
            indices: SIMD4(0, .max, .max, .max))
        XCTAssertThrowsError(try fixture.referenceSkinnedMesh(modelFromJoint: []))
        XCTAssertThrowsError(try fixture.referenceSkinnedMesh(modelFromJoint: [[1]]))
        var invalid = Self.identity
        invalid[12] = .infinity
        XCTAssertThrowsError(try fixture.referenceSkinnedMesh(modelFromJoint: [invalid]))
        invalid = Self.identity
        invalid[3] = 0.1
        XCTAssertThrowsError(try fixture.referenceSkinnedMesh(modelFromJoint: [invalid]))
        invalid = Self.identity
        invalid[0] = -1
        XCTAssertThrowsError(try fixture.referenceSkinnedMesh(modelFromJoint: [invalid]))
        let unaligned = GeneratedRig(
            mesh: fixture.mesh, joints: fixture.joints, influences: [], eyelidsGenerated: false)
        XCTAssertThrowsError(try unaligned.referenceSkinnedMesh(modelFromJoint: [Self.identity]))
        for (weight, index) in [(Float(1), UInt32(1)), (0.75, 0), (.nan, 0), (-1, 0), (0, 0)] {
            let malformed = rig(
                rest: [Self.identity], inverse: [Self.identity], weights: SIMD4(weight, 0, 0, 0),
                indices: SIMD4(index, .max, .max, .max))
            XCTAssertThrowsError(try malformed.referenceSkinnedMesh(modelFromJoint: [Self.identity]))
        }
    }
}
