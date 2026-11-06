import XCTest
import simd

@testable import Dust3DKit
@testable import Dust3DRendering

final class MeshDrawRangeTests: XCTestCase {
    func testFullSkeletonBodyAndEmptySpansKeepOriginalVertexOffsets() throws {
        for (range, start, count): (Range<Int>?, Int, Int) in [
            (nil, 0, 12), (0..<6, 0, 6), (6..<12, 6, 6), (0..<0, 0, 0), (12..<12, 12, 0),
        ] {
            let span = try MeshDrawRange(vertexCount: 12, range: range)
            XCTAssertEqual(span.vertexStart, start)
            XCTAssertEqual(span.vertexCount, count)
        }
        XCTAssertEqual(try MeshDrawRange(vertexCount: 0, range: nil).vertexCount, 0)
        // The nil policy is also retained by indexed renderers with four shared vertices.
        XCTAssertEqual(try MeshDrawRange(vertexCount: 4, range: nil).vertexCount, 4)
    }

    func testInvalidBoundsAndPartialTrianglesRejectBeforeEncoding() {
        for range in [-3..<0, 0..<15, 1..<3, 0..<4, 3..<7] {
            XCTAssertThrowsError(try MeshDrawRange(vertexCount: 12, range: range)) {
                XCTAssertTrue($0 is RendererError)
                XCTAssertFalse($0.localizedDescription.isEmpty)
            }
        }
        XCTAssertThrowsError(try MeshDrawRange(vertexCount: -1, range: nil))
    }

    func testInvalidSpanStopsDrawingAndValidSpanRestoresWithoutReplacingSource() throws {
        var state = MeshDrawRangeState()
        try state.update(vertexCount: 12, range: 6..<12)
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(state.span.vertexStart, 6)
        XCTAssertEqual(state.span.vertexCount, 6)
        XCTAssertThrowsError(try state.update(vertexCount: 12, range: 0..<15))
        XCTAssertFalse(state.isValid)
        XCTAssertEqual(state.span.vertexCount, 0)
        try state.update(vertexCount: 12, range: 0..<3)
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(state.span.vertexStart, 0)
        XCTAssertEqual(state.span.vertexCount, 3)
        XCTAssertThrowsError(try state.update(vertexCount: 4, range: 0..<3, isIndexed: true))
        XCTAssertFalse(state.isValid)
        XCTAssertEqual(state.span.vertexCount, 0)
        try state.update(vertexCount: 4, range: nil, isIndexed: true)
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(state.span.vertexCount, 4)
    }

    func testRangeDiagnosticsAreOncePerRequestAndRejectABAEpochs() throws {
        var request = MeshDrawRangeRequestState()
        XCTAssertTrue(request.update(range: nil, meshRevision: 1))
        let first = try XCTUnwrap(request.captureFailure())
        XCTAssertTrue(request.accepts(first))
        XCTAssertNil(request.captureFailure())
        XCTAssertFalse(request.update(range: nil, meshRevision: 1))
        XCTAssertNil(request.captureFailure())
        XCTAssertTrue(request.update(range: 0..<3, meshRevision: 1))
        XCTAssertFalse(request.accepts(first))
        XCTAssertTrue(request.update(range: nil, meshRevision: 1))
        XCTAssertFalse(request.accepts(first))
        let current = try XCTUnwrap(request.captureFailure())
        XCTAssertTrue(request.accepts(current))
        request.succeeded()
        XCTAssertNotNil(request.captureFailure())
        XCTAssertTrue(request.update(range: nil, meshRevision: 2))
        XCTAssertFalse(request.accepts(current))
    }

    func testVisibilityPlansAddressTheSameFullStreamNormalization() throws {
        let mesh = Mesh(
            vertices: [
                vertex(-10, 0, 0), vertex(-9, 0, 0), vertex(-10, 1, 0),
                vertex(10, 0, 0), vertex(11, 0, 0), vertex(10, 1, 0),
            ], nodeCount: 0, partCount: 0, warning: "")
        let geometry = try RenderGeometry(mesh: .expanded(mesh))
        let body = try MeshDrawRange(vertexCount: geometry.vertices.count, range: 3..<6)
        let bones = try MeshDrawRange(vertexCount: geometry.vertices.count, range: 0..<3)
        XCTAssertEqual(geometry.vertices.count, 6)
        XCTAssertEqual(body.vertexStart, 3)
        XCTAssertEqual(bones.vertexCount, 3)
        let fullBounds = try RenderBounds(vertices: mesh.vertices)
        XCTAssertEqual(
            geometry.vertices[body.vertexStart].position,
            SIMD4((mesh.vertices[3].position - fullBounds.center) / fullBounds.radius, 1))
        XCTAssertEqual(
            geometry.vertices[bones.vertexStart].position,
            SIMD4((mesh.vertices[0].position - fullBounds.center) / fullBounds.radius, 1))
        XCTAssertGreaterThan(geometry.vertices[body.vertexStart].position.x, 0)
        XCTAssertLessThan(geometry.vertices[bones.vertexStart].position.x, 0)
    }

    @MainActor
    func testExpandedViewportOptsIntoRangeWhileDefaultAndIndexedKeepFullDraw() {
        let mesh = Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: "")
        let selected = MeshViewport(
            mesh: mesh, isWireframe: false, cameraReset: 0, drawRange: 3..<6, onError: { _ in })
        let ordinary = MeshViewport(mesh: mesh, isWireframe: false, cameraReset: 0, onError: { _ in })
        let indexed = IndexedMesh(vertices: [], indices: [], nodeCount: 0, partCount: 0, warning: "")
        let materials = MeshViewport(
            mesh: indexed, isWireframe: false, cameraReset: 0, materials: nil, onError: { _ in })
        XCTAssertEqual(selected.drawRange, 3..<6)
        XCTAssertNil(ordinary.drawRange)
        XCTAssertNil(materials.drawRange)
    }

    private func vertex(_ x: Float, _ y: Float, _ z: Float) -> MeshVertex {
        MeshVertex(position: SIMD3(x, y, z), normal: SIMD3(0, 0, 1), color: .one)
    }
}
