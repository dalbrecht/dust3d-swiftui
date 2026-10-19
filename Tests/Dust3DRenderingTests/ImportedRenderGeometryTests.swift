import Foundation
import XCTest
import simd

@testable import Dust3DKit
@testable import Dust3DRendering

final class ImportedRenderGeometryTests: XCTestCase {
    func test_should_keep_source_uvs_linear_colors_and_material_factors_separate() throws {
        let data = try importedRenderFixture()
        let geometry = try ImportedRenderGeometry(data: data)
        XCTAssertEqual(geometry.vertices.count, 3)
        XCTAssertEqual(geometry.vertices[0].textureCoordinate, SIMD4(-0.25, 1.25, 1, 0))
        XCTAssertEqual(geometry.vertices[0].color, SIMD4(0.5, 0.25, 0.75, 0.4))
        XCTAssertEqual(geometry.materials.count, 2)
        XCTAssertEqual(geometry.materials[0].uniforms.baseColor, SIMD4(0.25, 0.5, 0.75, 0.5))
        XCTAssertEqual(geometry.materials[0].uniforms.emissiveMetallic, SIMD4(0.1, 0.2, 0.3, 0.125))
        XCTAssertEqual(geometry.materials[0].uniforms.parameters, SIMD4(0.625, 0.375, 0, 1))
        XCTAssertFalse(geometry.materials[0].isDoubleSided)
        XCTAssertEqual(geometry.materials[0].image?.mipmapLevelCount, 2)
        XCTAssertEqual(geometry.materials[0].image?.payloadBytes, 20)
        XCTAssertEqual(geometry.materials[0].image?.pixels, data.materials[0].image?.pixels)
        XCTAssertFalse(geometry.triangles[0].isTransparent)
        XCTAssertTrue(
            geometry.vertices.allSatisfy { simd_length(SIMD3($0.position.x, $0.position.y, $0.position.z)) <= 1.00001 })
    }

    func test_should_decode_srgb_before_vertex_interpolation_without_changing_alpha() throws {
        let geometry = try ImportedRenderGeometry(data: importedRenderFixture(encoding: .sRGB))
        let color = geometry.vertices[0].color
        XCTAssertEqual(color.x, 0.21404114, accuracy: 0.000001)
        XCTAssertEqual(color.y, 0.05087609, accuracy: 0.000001)
        XCTAssertEqual(color.z, 0.52252155, accuracy: 0.000001)
        XCTAssertEqual(color.w, 0.4)
        XCTAssertThrowsError(try ImportedRenderGeometry(data: importedRenderFixture(color: SIMD4(.nan, 0, 0, 1))))
        XCTAssertThrowsError(try ImportedRenderGeometry(data: importedRenderFixture(color: SIMD4(0, 0, 0, 1.01))))
    }

    func test_should_map_all_sampler_filters_and_axis_modes_without_metal() {
        let expected: [(ImportedMinificationFilter, ImportedSamplerPlan.Filter, ImportedSamplerPlan.MipFilter)] = [
            (.nearest, .nearest, .none), (.linear, .linear, .none),
            (.nearestMipmapNearest, .nearest, .nearest), (.linearMipmapNearest, .linear, .nearest),
            (.nearestMipmapLinear, .nearest, .linear), (.linearMipmapLinear, .linear, .linear),
        ]
        for (filter, minimum, mip) in expected {
            let plan = ImportedSamplerPlan(
                sampler: ImportedTextureSampler(
                    magnification: .nearest, minification: filter, wrapS: .clampToEdge, wrapT: .mirroredRepeat))
            XCTAssertEqual(plan.minification, minimum)
            XCTAssertEqual(plan.mip, mip)
            XCTAssertEqual(plan.magnification, .nearest)
            XCTAssertEqual(plan.wrapS, .clampToEdge)
            XCTAssertEqual(plan.wrapT, .mirroredRepeat)
        }
        let defaults = ImportedSamplerPlan(sampler: nil)
        XCTAssertEqual(defaults.magnification, .linear)
        XCTAssertEqual(defaults.minification, .linear)
        XCTAssertEqual(defaults.mip, .linear)
        XCTAssertEqual(defaults.wrapS, .repeatTexture)
        XCTAssertEqual(defaults.wrapT, .repeatTexture)
    }

    func test_should_route_alpha_by_material_policy_and_fallback_without_inventing_uvs() throws {
        let opaque = try ImportedRenderGeometry(data: importedRenderFixture(modes: [.opaque]))
        let masked = try ImportedRenderGeometry(data: importedRenderFixture(modes: [.mask]))
        let blended = try ImportedRenderGeometry(data: importedRenderFixture(modes: [.blend]))
        XCTAssertFalse(opaque.triangles[0].isTransparent)
        XCTAssertFalse(masked.triangles[0].isTransparent)
        XCTAssertTrue(blended.triangles[0].isTransparent)
        XCTAssertEqual(masked.materials[0].uniforms.parameters.z, 1)
        XCTAssertEqual(blended.materials[0].uniforms.parameters.z, 2)
        let fallback = try ImportedRenderGeometry(data: importedRenderFixture(triangleMaterials: [nil]))
        XCTAssertEqual(fallback.triangles[0].materialIndex, 1)
        XCTAssertEqual(fallback.vertices[0].textureCoordinate, .zero)
        XCTAssertTrue(fallback.triangles[0].isTransparent)
        XCTAssertTrue(fallback.materials[1].isDoubleSided)
        XCTAssertNil(fallback.materials[1].image)
    }

    func test_should_admit_exact_payload_and_reject_invalid_limits_and_device_buffers() throws {
        let data = try importedRenderFixture()
        let geometry = try ImportedRenderGeometry(data: data)
        XCTAssertEqual(
            try ImportedRenderGeometry(data: data, maximumPayloadBytes: geometry.payloadBytes).payloadBytes,
            geometry.payloadBytes)
        XCTAssertThrowsError(try ImportedRenderGeometry(data: data, maximumPayloadBytes: geometry.payloadBytes - 1))
        XCTAssertThrowsError(try ImportedRenderGeometry(data: data, maximumPayloadBytes: 0))
        XCTAssertThrowsError(try ImportedRenderGeometry(data: data, maximumPayloadBytes: Int.max))
        XCTAssertThrowsError(try geometry.validateBufferLengths(maximumBufferLength: 1))
        try geometry.validateBufferLengths(maximumBufferLength: 4096)
        let noMips = try ImportedRenderGeometry(data: importedRenderFixture(minification: .linear))
        XCTAssertEqual(noMips.materials[0].image?.mipmapLevelCount, 1)
        XCTAssertEqual(noMips.materials[0].image?.payloadBytes, 16)
    }

    func test_should_preserve_original_bounds_failure_message() {
        let error = RendererError.unavailable("Original finite bounds cause")
        XCTAssertEqual(error.localizedDescription, "Original finite bounds cause")
    }

    func test_should_sort_blended_triangles_globally_before_coalescing_material_draws() throws {
        let geometry = try ImportedRenderGeometry(
            data: importedRenderFixture(
                modes: [.blend, .blend], triangleMaterials: [0, 1, 0], depths: [-0.5, 0.5, 0]))
        let order = try ImportedTriangleOrder(geometry: geometry)
        XCTAssertTrue(order.opaque.indices.isEmpty)
        let forward = try order.transparent(rotation: matrix_identity_float4x4)
        XCTAssertEqual(forward.indices, [0, 1, 2, 6, 7, 8, 3, 4, 5])
        XCTAssertEqual(forward.batches.map(\.materialIndex), [0, 1])
        XCTAssertEqual(forward.batches.map(\.indexCount), [6, 3])
        XCTAssertEqual(forward.batches.map(\.indexOffset), [0, 6])
        let rotation = simd_float4x4(diagonal: SIMD4(-1, 1, -1, 1))
        let back = try order.transparent(rotation: rotation)
        XCTAssertEqual(back.indices, [3, 4, 5, 6, 7, 8, 0, 1, 2])
        XCTAssertEqual(back.batches.map(\.materialIndex), [1, 0])
        var invalid = matrix_identity_float4x4
        invalid.columns.0.x = .nan
        XCTAssertThrowsError(try order.transparent(rotation: invalid))
    }
}
