import XCTest
import simd

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class MeshPickingGeometryTests: XCTestCase {
    private let orthographic = simd_float4x4(
        columns: (
            SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, -0.5, 0), SIMD4(0, 0, 0.5, 1)
        ))
    private func triangle(z: Float = 0, center: SIMD2<Float> = .zero, scale: Float = 1) -> [MeshVertex] {
        [
            SIMD3(-scale + center.x, -scale + center.y, z),
            SIMD3(scale + center.x, -scale + center.y, z), SIMD3(center.x, scale + center.y, z),
        ]
        .map { MeshVertex(position: $0, normal: SIMD3(0, 0, 1), color: .one) }
    }
    private func mesh(_ vertices: [MeshVertex]) -> Mesh {
        Mesh(vertices: vertices, nodeCount: 0, partCount: 0, warning: "")
    }
    private func input(point: SIMD2<Float> = SIMD2(50, 50), transform: simd_float4x4? = nil) -> MeshPickInput {
        MeshPickInput(point: point, size: SIMD2(100, 100), transform: transform ?? orthographic)
    }
    private func screenPoint(_ point: SIMD3<Float>, mesh: Mesh, transform: simd_float4x4) throws -> SIMD2<Float> {
        let bounds = try RenderBounds(vertices: mesh.vertices)
        let clip = transform * SIMD4((point - bounds.center) / bounds.radius, 1)
        return SIMD2((clip.x / clip.w + 1) * 50, (clip.y / clip.w + 1) * 50)
    }

    func testNearestBodyOccludesBoneAndVisibleSpansKeepSourceOwners() throws {
        let geometry = try MeshPickingGeometry(
            mesh: mesh(triangle(z: 0) + triangle(z: 0.5)), skeletonTriangleOwners: [2], jointCount: 3)
        XCTAssertTrue(geometry.hasBones)
        XCTAssertEqual(try geometry.pick(input(), drawRange: nil), .body)
        XCTAssertEqual(try geometry.pick(input(), drawRange: 0..<3), .bone(2))
        XCTAssertEqual(try geometry.pick(input(), drawRange: 3..<6), .body)
        XCTAssertEqual(try geometry.pick(input(), drawRange: 0..<0), .miss)
    }

    func testNearestBoneWinsAndCoplanarTiesRetainSourceOrder() throws {
        let front = try MeshPickingGeometry(
            mesh: mesh(triangle(z: 0.5) + triangle(z: 0)), skeletonTriangleOwners: [1, 0], jointCount: 2)
        XCTAssertEqual(try front.pick(input(), drawRange: nil), .bone(1))
        let tied = try MeshPickingGeometry(
            mesh: mesh(triangle() + triangle() + triangle()), skeletonTriangleOwners: [1, 0], jointCount: 2)
        XCTAssertEqual(try tied.pick(input(), drawRange: nil), .bone(1))
        XCTAssertEqual(try tied.pick(input(), drawRange: 3..<9), .bone(0))
    }

    func testTwoSidedTrianglesTranslatedSourceAndPerspectiveCamera() throws {
        let shifted = triangle().reversed().map {
            MeshVertex(position: $0.position + SIMD3(100, 200, 300), normal: $0.normal, color: $0.color)
        }
        let geometry = try MeshPickingGeometry(mesh: mesh(shifted), skeletonTriangleOwners: [0], jointCount: 1)
        XCTAssertEqual(try geometry.pick(input(), drawRange: nil), .bone(0))
        let perspective = OrbitCamera(yaw: 0, pitch: 0, distance: 3).transform(aspect: 1)
        XCTAssertEqual(try geometry.pick(input(transform: perspective), drawRange: nil), .bone(0))
    }

    func testBottomLeftViewCoordinatesDistinguishUpperAndLowerBones() throws {
        let source = mesh(triangle(center: SIMD2(0, 1), scale: 0.3) + triangle(center: SIMD2(0, -1), scale: 0.3))
        let geometry = try MeshPickingGeometry(mesh: source, skeletonTriangleOwners: [0, 1], jointCount: 2)
        let upper = try screenPoint(SIMD3(0, 1, 0), mesh: source, transform: orthographic)
        let lower = try screenPoint(SIMD3(0, -1, 0), mesh: source, transform: orthographic)
        XCTAssertGreaterThan(upper.y, lower.y)
        XCTAssertEqual(try geometry.pick(input(point: upper), drawRange: nil), .bone(0))
        XCTAssertEqual(try geometry.pick(input(point: lower), drawRange: nil), .bone(1))
        XCTAssertEqual(try geometry.pick(input(), drawRange: nil), .miss)
    }

    func testBodyOnlyDegenerateAndTinyTrianglesAreSafe() throws {
        let body = try MeshPickingGeometry(mesh: mesh(triangle()), skeletonTriangleOwners: [], jointCount: 0)
        XCTAssertFalse(body.hasBones)
        XCTAssertEqual(try body.pick(input(), drawRange: nil), .body)
        let vertex = MeshVertex(position: .zero, normal: SIMD3(0, 0, 1), color: .one)
        let degenerate = try MeshPickingGeometry(
            mesh: mesh([vertex, vertex, vertex]), skeletonTriangleOwners: [0], jointCount: 1)
        XCTAssertEqual(try degenerate.pick(input(), drawRange: nil), .miss)
        let tiny = try MeshPickingGeometry(
            mesh: mesh(triangle(scale: 1e-20)), skeletonTriangleOwners: [0], jointCount: 1)
        XCTAssertEqual(try tiny.pick(input(), drawRange: nil), .bone(0))
    }

    func testOutsideInvalidAndNonfiniteInputsReturnMiss() throws {
        let geometry = try MeshPickingGeometry(mesh: mesh(triangle()), skeletonTriangleOwners: [0], jointCount: 1)
        for point: SIMD2<Float> in [SIMD2(-1, 50), SIMD2(101, 50), SIMD2(50, -1), SIMD2(50, 101), SIMD2(.nan, 50)] {
            XCTAssertEqual(try geometry.pick(input(point: point), drawRange: nil), .miss)
        }
        for size: SIMD2<Float> in [.zero, SIMD2(-100, 100), SIMD2(100, .infinity)] {
            XCTAssertEqual(
                try geometry.pick(
                    MeshPickInput(point: SIMD2(50, 50), size: size, transform: orthographic), drawRange: nil),
                .miss)
        }
        var nonfinite = orthographic
        nonfinite.columns.0.x = .nan
        // A globally negated clip matrix has the same divided coordinates but
        // negative clip W: the renderer clips it rather than showing the mesh.
        let behind = simd_float4x4(
            columns: (
                -orthographic.columns.0, -orthographic.columns.1, -orthographic.columns.2, -orthographic.columns.3
            ))
        for transform in [nonfinite, behind, simd_float4x4(columns: (.zero, .zero, .zero, .zero))] {
            XCTAssertEqual(try geometry.pick(input(transform: transform), drawRange: nil), .miss)
        }
    }

    func testTrianglesOutsideNearFarClipSegmentDoNotPick() throws {
        let geometry = try MeshPickingGeometry(mesh: mesh(triangle()), skeletonTriangleOwners: [0], jointCount: 1)
        for depth: Float in [-2, 2] {
            var transform = orthographic
            transform.columns.3.z = depth
            XCTAssertEqual(try geometry.pick(input(transform: transform), drawRange: nil), .miss)
        }
    }

    func testMalformedMeshOwnerMetadataAndRangesReject() throws {
        for vertices in [
            [], Array(triangle().prefix(2)),
            [
                MeshVertex(position: SIMD3(.nan, 0, 0), normal: SIMD3(0, 0, 1), color: .one)
            ] + Array(triangle().prefix(2)),
        ] {
            XCTAssertThrowsError(
                try MeshPickingGeometry(mesh: mesh(vertices), skeletonTriangleOwners: [], jointCount: 0))
        }
        for (owners, count): ([UInt32], Int) in [([], -1), ([], 257), ([0, 0], 1), ([0], 0), ([1], 1), ([.max], 1)] {
            XCTAssertThrowsError(
                try MeshPickingGeometry(mesh: mesh(triangle()), skeletonTriangleOwners: owners, jointCount: count))
        }
        let geometry = try MeshPickingGeometry(mesh: mesh(triangle()), skeletonTriangleOwners: [0], jointCount: 1)
        for range in [-3..<0, 0..<6, 1..<3] {
            XCTAssertThrowsError(try geometry.pick(input(), drawRange: range))
        }
    }

    func testPrecancelledPreparationAndPickingThrowCancellation() async throws {
        let source = mesh(triangle())
        let geometry = try MeshPickingGeometry(mesh: source, skeletonTriangleOwners: [0], jointCount: 1)
        let pickInput = input()
        let preparation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try MeshPickingGeometry(mesh: source, skeletonTriangleOwners: [0], jointCount: 1)
        }
        do {
            _ = try await preparation.value
            XCTFail("Expected preparation cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let picking = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try geometry.pick(pickInput, drawRange: nil)
        }
        do {
            _ = try await picking.value
            XCTFail("Expected picking cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
