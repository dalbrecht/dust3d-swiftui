import Foundation
import XCTest
import simd

@testable import Dust3DKit
@testable import Dust3DRendering

final class ImportedRenderValidationTests: XCTestCase {
    func test_should_reject_invalid_pixel_views_before_unsafe_gpu_upload() throws {
        let id = try ImportedSurfaceIdentity(rawValue: "model")
        // Every backing buffer is explicitly at most 15 bytes, independent of invalid metadata.
        let tiny = Data(repeating: 0, count: 4)
        let truncated = Data(repeating: 0, count: 15)
        let cases: [(Int, Int, Int, Data)] = [
            (0, 1, 4, tiny), (1, 0, 4, tiny), (8193, 1, 4, tiny), (1, 8193, 4, tiny),
            (2, 1, 4, tiny), (1, 1, 5, tiny), (2, 2, 8, truncated),
        ]
        for (width, height, stride, pixels) in cases {
            let source = ImportedDecodedImage(
                modelID: id.rawValue, width: width, height: height, rowStride: stride, pixels: pixels)
            XCTAssertThrowsError(try ImportedRenderImage(source: source, id: id, mipmapped: true)) {
                XCTAssertEqual($0 as? ImportedRenderError, .invalidImage)
            }
        }
        let mismatched = ImportedDecodedImage(modelID: "different", width: 1, height: 1, rowStride: 4, pixels: tiny)
        XCTAssertThrowsError(try ImportedRenderImage(source: mismatched, id: id, mipmapped: false))
        let padded = ImportedDecodedImage(
            modelID: id.rawValue, width: 1, height: 2, rowStride: 8, pixels: Data(repeating: 255, count: 12))
        let valid = try ImportedRenderImage(source: padded, id: id, mipmapped: true)
        XCTAssertEqual(valid.payloadBytes, 12)
        XCTAssertEqual(valid.mipmapLevelCount, 2)
    }

    func test_should_preserve_each_corner_color_and_reject_invalid_source_channels() throws {
        let source = try importedRenderFixture()
        let original = try XCTUnwrap(source.surface.triangles.first)
        let colors = ImportedSurfaceColors(
            first: SIMD4(1, 0, 0, 0.2), second: SIMD4(0, 1, 0, 0.4), third: SIMD4(0, 0, 1, 0.6))
        let triangle = ImportedSurfaceTriangle(
            sourceUVs: original.sourceUVs, colors: colors, colorEncoding: .linear, modelIndex: 0, componentIndex: 0)
        let prepared = try ImportedRenderGeometry(data: replacing(source, triangles: [triangle]))
        XCTAssertEqual(prepared.vertices.map(\.color), [SIMD4(1, 0, 0, 0.2), SIMD4(0, 1, 0, 0.4), SIMD4(0, 0, 1, 0.6)])
        XCTAssertEqual(
            prepared.vertices.map(\.textureCoordinate),
            [SIMD4(-0.25, 1.25, 1, 0), SIMD4(1, 0, 1, 0), SIMD4(0, 1, 1, 0)])
        for model in [nil, -1, 1] as [Int?] {
            let invalid = ImportedSurfaceTriangle(
                sourceUVs: original.sourceUVs, colors: colors, colorEncoding: .linear, modelIndex: model,
                componentIndex: 0)
            XCTAssertThrowsError(try ImportedRenderGeometry(data: replacing(source, triangles: [invalid])))
        }
        let unmapped = ImportedSurfaceTriangle(
            sourceUVs: nil, colors: colors, colorEncoding: .linear, modelIndex: 0, componentIndex: 0)
        XCTAssertThrowsError(try ImportedRenderGeometry(data: replacing(source, triangles: [unmapped])))
        XCTAssertThrowsError(try ImportedRenderGeometry(data: replacing(source, triangles: [])))
        let originalVertex = source.surface.mesh.vertices[0]
        var vertices = source.surface.mesh.vertices
        vertices[0] = MeshVertex(
            position: SIMD3(.nan, 0, 0), normal: originalVertex.normal, color: originalVertex.color)
        XCTAssertThrowsError(
            try ImportedRenderGeometry(
                data: replacing(source, mesh: Mesh(vertices: vertices, nodeCount: 2, partCount: 1, warning: ""))))
    }

    func test_should_report_material_catalog_mismatch_as_material_failure() throws {
        let source = try importedRenderFixture()
        XCTAssertThrowsError(try ImportedRenderGeometry(data: replacing(source, materials: []))) {
            XCTAssertEqual($0 as? ImportedRenderError, .invalidMaterial)
        }
    }

    func test_should_bound_material_objects_and_interleaved_draw_submission() throws {
        // Bounded synthetic values: 4097 small records, not an oversized pixel allocation.
        let many = try importedRenderFixture(modes: Array(repeating: .opaque, count: 4097))
        XCTAssertThrowsError(try ImportedRenderGeometry(data: many)) {
            XCTAssertEqual($0 as? ImportedRenderError, .bindingLimit)
        }
        let admitted = try importedRenderFixture(modes: Array(repeating: .opaque, count: 4096))
        XCTAssertEqual(try ImportedRenderGeometry(data: admitted).materials.count, 4097)
        let atLimit = try importedRenderFixture(
            modes: [.opaque, .opaque], triangleMaterials: (0..<4096).map { $0 % 2 },
            depths: Array(repeating: 0, count: 4096))
        let admittedOrder = try ImportedTriangleOrder(geometry: ImportedRenderGeometry(data: atLimit))
        XCTAssertEqual(admittedOrder.opaque.batches.count, 4096)
        for mode in [ImportedAlphaMode.opaque, .blend] {
            let data = try importedRenderFixture(
                modes: [mode, mode], triangleMaterials: (0..<4097).map { $0 % 2 },
                depths: Array(repeating: 0, count: 4097))
            let geometry = try ImportedRenderGeometry(data: data)
            XCTAssertThrowsError(
                try {
                    let order = try ImportedTriangleOrder(geometry: geometry)
                    _ = try order.transparent(rotation: matrix_identity_float4x4)
                }())
        }
    }

    private func replacing(
        _ value: ImportedMaterialRenderData, mesh: Mesh? = nil, triangles: [ImportedSurfaceTriangle]? = nil,
        materials: [ImportedRenderMaterial]? = nil
    ) -> ImportedMaterialRenderData {
        let original = value.surface
        let surface = ImportedSurfaceMesh(
            mesh: mesh ?? original.mesh, triangles: triangles ?? original.triangles, modelIDs: original.modelIDs,
            components: original.components, nativePayloadBytes: original.nativePayloadBytes,
            copiedPayloadBytes: original.copiedPayloadBytes)
        return ImportedMaterialRenderData(
            surface: surface, materials: materials ?? value.materials, decodedPayloadBytes: value.decodedPayloadBytes)
    }
}
