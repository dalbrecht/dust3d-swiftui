import XCTest
import simd

@testable import Dust3DKit
@testable import Dust3DRendering

final class RenderGeometryTests: XCTestCase {
    func testIndexedPreparationPreservesReferencesAttributesAndNormalizedBounds() throws {
        let source = [vertex(2, 4, 6), vertex(4, 4, 6), vertex(2, 6, 6)]
        let geometry = try RenderGeometry(
            mesh: .indexed(
                IndexedMesh(
                    vertices: source, indices: [0, 1, 2, 2, 1, 0], nodeCount: 3, partCount: 1, warning: "")))
        XCTAssertEqual(geometry.indices, [0, 1, 2, 2, 1, 0])
        XCTAssertEqual(geometry.vertices.count, 3)
        XCTAssertEqual(geometry.vertices[0].position, SIMD4(-1 / sqrt(2), -1 / sqrt(2), 0, 1))
        XCTAssertEqual(geometry.vertices[0].normal, SIMD4(0, 0, 1, 0))
        XCTAssertEqual(geometry.vertices[0].color, source[0].color)
        XCTAssertTrue(
            geometry.vertices.allSatisfy { simd_length(SIMD3($0.position.x, $0.position.y, $0.position.z)) <= 1.00001 })
    }

    func testExpandedPreparationRetainsTriangleOrderAndSmallBoundsRemainFinite() throws {
        let geometry = try RenderGeometry(
            mesh: .expanded(
                Mesh(
                    vertices: [vertex(0, 0, 0), vertex(0, 0, 0), vertex(0, 0, 0)], nodeCount: 1, partCount: 1,
                    warning: "")))
        XCTAssertNil(geometry.indices)
        XCTAssertEqual(geometry.vertices.count, 3)
        XCTAssertTrue(geometry.vertices.allSatisfy { $0.position == SIMD4(0, 0, 0, 1) })
    }

    func testInvalidTriangleBuffersAreRejectedBeforeGPUAllocation() {
        for indices: [UInt32] in [[], [0, 1], [0, 1, 3]] {
            XCTAssertThrowsError(
                try RenderGeometry(
                    mesh: .indexed(
                        IndexedMesh(
                            vertices: [vertex(0, 0, 0), vertex(1, 0, 0), vertex(0, 1, 0)],
                            indices: indices, nodeCount: 3, partCount: 1, warning: ""))))
        }
        for vertices in [[], [vertex(0, 0, 0)], [vertex(.nan, 0, 0), vertex(1, 0, 0), vertex(0, 1, 0)]] {
            XCTAssertThrowsError(
                try RenderGeometry(
                    mesh: .expanded(
                        Mesh(
                            vertices: vertices, nodeCount: 0, partCount: 0, warning: ""))))
        }
    }

    func testUnrepresentableBoundsAreRejected() {
        let source = [
            vertex(-Float.greatestFiniteMagnitude, 0, 0), vertex(Float.greatestFiniteMagnitude, 0, 0), vertex(0, 1, 0),
        ]
        XCTAssertThrowsError(
            try RenderGeometry(mesh: .expanded(Mesh(vertices: source, nodeCount: 3, partCount: 1, warning: ""))))
    }

    private func vertex(_ x: Float, _ y: Float, _ z: Float) -> MeshVertex {
        MeshVertex(position: SIMD3(x, y, z), normal: SIMD3(0, 0, 1), color: SIMD4(0.2, 0.4, 0.8, 1))
    }
}
