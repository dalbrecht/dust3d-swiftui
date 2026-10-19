import Foundation
import Metal
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

final class BakedMipUploadPlanTests: XCTestCase {
    func testPreflightsEveryRetainedLevelAndExactCombinedBudget() throws {
        let source = try fixture(lod: 2)
        let chain = try TextureMipChain(
            levels: [source.textures.color, image(2, 71), image(1, 19)], maximumSamplingLod: 2)
        let geometry = try TexturedRenderGeometry(bakedMesh: source)
        let plan = try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max, mipmaps: [0: chain])
        XCTAssertEqual(plan.imageLevels.map(\.count), [3, 1, 1, 1, 1])
        XCTAssertEqual(plan.imageLevels[0].map(\.width), [4, 2, 1])
        XCTAssertEqual(plan.maximumSamplingLod, 2)
        XCTAssertTrue(plan.usesMipFiltering)
        let base = try BakedMetalUploadPlan(
            geometry: TexturedRenderGeometry(bakedMesh: fixture(lod: 0)), maximumBufferLength: Int.max)
        XCTAssertEqual(plan.payloadBytes, base.payloadBytes + 20)
        XCTAssertNoThrow(
            try BakedMetalUploadPlan(
                geometry: geometry, maximumBufferLength: Int.max, maximumPayloadBytes: plan.payloadBytes,
                mipmaps: [0: chain]))
        XCTAssertThrowsError(
            try BakedMetalUploadPlan(
                geometry: geometry, maximumBufferLength: Int.max, maximumPayloadBytes: plan.payloadBytes - 1,
                mipmaps: [0: chain]))
    }

    func testRejectsMissingMismatchedAndInsufficientChainsBeforeMetalAllocation() throws {
        let source = try fixture(lod: 1)
        let geometry = try TexturedRenderGeometry(bakedMesh: source)
        XCTAssertThrowsError(try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max))
        let wrongBase = try TextureMipChain(levels: [image(4, 99), image(2, 3)], maximumSamplingLod: 1)
        XCTAssertThrowsError(
            try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max, mipmaps: [0: wrongBase]))
        XCTAssertThrowsError(
            try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max, mipmaps: [1: wrongBase]))
        let unavailable = try TextureMipChain(levels: [source.textures.color, image(2, 3)], maximumSamplingLod: 0.5)
        XCTAssertThrowsError(
            try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max, mipmaps: [0: unavailable]))
        XCTAssertThrowsError(
            try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max, mipmaps: [5: wrongBase]))
    }

    func testRoundsSamplingCapDownAndPreservesBaseOnlyDefaults() throws {
        let source = try fixture(lod: 0.1)
        let chain = try TextureMipChain(levels: [source.textures.color, image(2, 71)], maximumSamplingLod: 0.1)
        let plan = try BakedMetalUploadPlan(
            geometry: TexturedRenderGeometry(bakedMesh: source), maximumBufferLength: Int.max, mipmaps: [0: chain])
        XCTAssertLessThanOrEqual(Double(plan.maximumSamplingLod), 0.1)
        XCTAssertTrue(plan.usesMipFiltering)
        let base = try BakedMetalUploadPlan(
            geometry: TexturedRenderGeometry(bakedMesh: fixture(lod: 0)), maximumBufferLength: Int.max)
        XCTAssertEqual(base.maximumSamplingLod, 0)
        XCTAssertFalse(base.usesMipFiltering)
        XCTAssertEqual(base.imageLevels.map(\.count), [1, 1, 1, 1, 1])
    }

    func testRequiresEveryPresentMapChainAndIncludesMipAlphaInDrawRouting() throws {
        let base = image(4, 255)
        let baked = try BakedMetalFixture.quad(
            color: base, normal: base, metallic: base, roughness: base, emissive: base)
        let original = BakedMetalFixture.source(baked, policy: nil)
        let source = SourceBakedMesh(
            geometry: original.geometry, triangles: original.triangles, modelIDs: [], components: [],
            textures: original.textures, maximumSamplingLod: 1, nativePayloadBytes: 0, copiedPayloadBytes: 0)
        let chain = try TextureMipChain(levels: [base, image(2, 71)], maximumSamplingLod: 1)
        let chains = Dictionary(uniqueKeysWithValues: (0..<5).map { ($0, chain) })
        let geometry = try TexturedRenderGeometry(bakedMesh: source)
        let plan = try BakedMetalUploadPlan(geometry: geometry, maximumBufferLength: Int.max, mipmaps: chains)
        XCTAssertTrue(
            plan.hasTransparentColor, "Unknown policies must account for transparency introduced in minified levels")
        XCTAssertTrue(plan.normalMapEnabled)
        XCTAssertEqual(plan.imageLevels.map(\.count), [2, 2, 2, 2, 2])
        XCTAssertEqual(plan.imageLevels[1].map(\.pixelFormat), [.rgba8Unorm, .rgba8Unorm])
        XCTAssertEqual(plan.imageLevels[4].map(\.pixelFormat), [.rgba8Unorm_srgb, .rgba8Unorm_srgb])
        for missing in 0..<5 {
            XCTAssertThrowsError(
                try BakedMetalUploadPlan(
                    geometry: geometry, maximumBufferLength: Int.max, mipmaps: chains.filter { $0.key != missing }))
        }
    }

    private func image(_ side: Int, _ value: UInt8) -> MeshTextureImage {
        MeshTextureImage(
            width: side, height: side, rowStride: side * 4, pixels: Data(repeating: value, count: side * side * 4))
    }

    private func fixture(lod: Double) throws -> SourceBakedMesh {
        let base = BakedMetalFixture.source(try BakedMetalFixture.quad(color: image(4, 255)), policy: nil)
        return SourceBakedMesh(
            geometry: base.geometry, triangles: base.triangles, modelIDs: [], components: [], textures: base.textures,
            maximumSamplingLod: lod, nativePayloadBytes: 0, copiedPayloadBytes: 0)
    }
}
