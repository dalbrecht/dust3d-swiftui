import Foundation
import Metal
import XCTest
import simd

@testable import Dust3DKit
@testable import Dust3DRendering

final class BakedMetalUploadPlanTests: XCTestCase {
    func testShouldPreflightAllMapSlotsFormatsAndExactCombinedBudget() throws {
        let geometry = try TexturedRenderGeometry(bakedMesh: BakedMetalFixture.quad())
        let plan = try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max)
        XCTAssertEqual(plan.images.count, 5)
        XCTAssertEqual(
            plan.images.map(\.pixelFormat), [.rgba8Unorm_srgb, .rgba8Unorm, .rgba8Unorm, .rgba8Unorm, .rgba8Unorm_srgb])
        XCTAssertEqual(plan.images[2].pixels, Data([0, 0, 0, 255]))
        XCTAssertEqual(plan.images[3].pixels, Data([255, 255, 255, 255]))
        XCTAssertEqual(plan.normalMapEnabled, false)
        XCTAssertFalse(plan.hasTransparentColor)
        let bytes =
            geometry.vertices.count * MemoryLayout<TexturedRenderGeometry.Vertex>.stride + geometry.indices.count * 4
            + 20
        XCTAssertEqual(plan.payloadBytes, bytes)
        XCTAssertNoThrow(
            try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max, maximumPayloadBytes: bytes))
        for limit in [-1, 0, bytes - 1, Int.max] {
            XCTAssertThrowsError(
                try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max, maximumPayloadBytes: limit))
        }
        XCTAssertThrowsError(try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: 1))
    }

    func testShouldRejectMalformedTextureViewsBeforeUnsafeAccessOrGPUAllocation() throws {
        for image in [
            MeshTextureImage(width: 0, height: 1, rowStride: 4, pixels: Data([1, 2, 3, 4])),
            MeshTextureImage(width: 8193, height: 1, rowStride: 32772, pixels: Data()),
            MeshTextureImage(width: 1, height: 1, rowStride: 3, pixels: Data([1, 2, 3])),
            MeshTextureImage(width: 1, height: 2, rowStride: Int.max, pixels: Data([1, 2, 3, 4])),
            MeshTextureImage(width: 1, height: 2, rowStride: 4, pixels: Data([1, 2, 3, 4])),
        ] {
            let geometry = try TexturedRenderGeometry(bakedMesh: BakedMetalFixture.quad(color: image))
            XCTAssertThrowsError(try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max))
        }
        let padded = MeshTextureImage(
            width: 1, height: 2, rowStride: 8, pixels: Data([255, 0, 0, 255, 0, 0, 0, 0, 0, 0, 255, 1]))
        let geometry = try TexturedRenderGeometry(bakedMesh: BakedMetalFixture.quad(color: padded))
        let plan = try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max)
        XCTAssertTrue(plan.hasTransparentColor)
        XCTAssertEqual(plan.images[0].rowStride, 8)
    }

    func testShouldPreserveOpaqueDepthGroupsAndSortTransparentTrianglesForCameraRotation() throws {
        let opaque = try TexturedRenderGeometry(bakedMesh: BakedMetalFixture.quad())
        let opaqueOrder = try BakedTriangleOrder(geometry: opaque, hasTransparentColor: false)
        XCTAssertEqual(opaqueOrder.opaqueIndices, opaque.indices)
        XCTAssertEqual(try opaqueOrder.transparentIndices(rotation: matrix_identity_float4x4), [])
        let source = try BakedMetalFixture.quad(
            color: BakedMetalFixture.image([255, 0, 0, 128]), layers: [.init(depth: 0.2), .init(depth: -0.2)])
        let geometry = try TexturedRenderGeometry(bakedMesh: source)
        let order = try BakedTriangleOrder(geometry: geometry, hasTransparentColor: true)
        XCTAssertEqual(order.opaqueIndices, [])
        let forward = try order.transparentIndices(rotation: matrix_identity_float4x4)
        XCTAssertEqual(Array(forward.prefix(6)), Array(geometry.indices.suffix(6)))
        let reversed = try order.transparentIndices(
            rotation: simd_float4x4(simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))))
        XCTAssertEqual(Array(reversed.prefix(6)), Array(geometry.indices.prefix(6)))
    }
    func testShouldRejectInvalidCameraDepthsAndUseVertexAlphaWithoutMapping() async throws {
        let source = try BakedMetalFixture.quad(
            mapped: false, layers: [.init(depth: 0.2, color: SIMD4(1, 0, 0, 0.5)), .init(depth: -0.2)])
        let geometry = try TexturedRenderGeometry(bakedMesh: source)
        let order = try BakedTriangleOrder(geometry: geometry, hasTransparentColor: true)
        XCTAssertEqual(order.opaqueIndices, Array(geometry.indices.suffix(6)))
        XCTAssertEqual(
            try order.transparentIndices(rotation: matrix_identity_float4x4), Array(geometry.indices.prefix(6)))
        var invalid = matrix_identity_float4x4
        invalid.columns.0.x = .nan
        XCTAssertThrowsError(try order.transparentIndices(rotation: invalid)) {
            XCTAssertEqual($0 as? BakedMetalPreparationError, .invalidCamera)
        }
        var overflow = matrix_identity_float4x4
        overflow.columns.2.z = .greatestFiniteMagnitude
        overflow.columns.3.z = .greatestFiniteMagnitude
        XCTAssertThrowsError(try order.transparentIndices(rotation: overflow))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try order.transparentIndices(rotation: matrix_identity_float4x4)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

}
