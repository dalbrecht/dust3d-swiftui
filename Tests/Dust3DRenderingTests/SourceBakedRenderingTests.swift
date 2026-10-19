import Foundation
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

final class SourceBakedRenderingTests: XCTestCase {
    func testPreservesFractionalLodAndBoundsItAgainstEveryPresentMap() throws {
        let base = try sourceQuad(policy: nil)
        let color = MeshTextureImage(width: 8, height: 8, rowStride: 32, pixels: Data(repeating: 255, count: 256))
        let normal = MeshTextureImage(width: 4, height: 4, rowStride: 16, pixels: Data(repeating: 128, count: 64))
        let maps = MeshTextureMaps(color: color, normal: nil, metallic: nil, roughness: nil, emissive: nil)
        XCTAssertEqual(
            try TexturedRenderGeometry(bakedMesh: replacing(base, textures: maps, lod: 2.5)).maximumSamplingLod, 2.5)
        let smallerMap = MeshTextureMaps(color: color, normal: normal, metallic: nil, roughness: nil, emissive: nil)
        XCTAssertNoThrow(try TexturedRenderGeometry(bakedMesh: replacing(base, textures: smallerMap, lod: 2)))
        XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: replacing(base, textures: smallerMap, lod: 2.1)))
        let invalid = MeshTextureImage(width: 0, height: 1, rowStride: 0, pixels: Data())
        XCTAssertThrowsError(
            try TexturedRenderGeometry(
                bakedMesh: replacing(
                    base,
                    textures: MeshTextureMaps(color: invalid, normal: nil, metallic: nil, roughness: nil, emissive: nil)
                )))
    }

    func testRejectsInvalidSourceCatalogsReferencesPoliciesUvsAndLodBeforeUpload() throws {
        let base = try sourceQuad(policy: .init(alphaMode: .opaque, alphaCutoff: 0.5, isDoubleSided: true))
        let first = try XCTUnwrap(base.triangles.first)
        let key = try ImportedSurfaceIdentity(rawValue: "model")
        let component = ImportedSurfaceComponent(id: key, kind: .original)
        for invalid in [
            replacing(base, models: [key, key]), replacing(base, components: [component, component]),
            replacing(base, triangles: []), replacing(base, lod: .nan), replacing(base, lod: .infinity),
            replacing(base, lod: -1), replacing(base, lod: 1),
        ] { XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: invalid)) }
        var badUv = try XCTUnwrap(first.packedUVs)
        badUv = MeshUvCorners(first: SIMD2(.nan, 0), second: badUv.second, third: badUv.third)
        let badRecords = [
            SourceBakedTriangle(
                packedUVs: first.packedUVs, tangent: first.tangent, policy: first.policy, modelIndex: 0,
                componentIndex: nil),
            SourceBakedTriangle(
                packedUVs: first.packedUVs, tangent: first.tangent, policy: first.policy, modelIndex: nil,
                componentIndex: -1),
            SourceBakedTriangle(
                packedUVs: first.packedUVs, tangent: first.tangent,
                policy: .init(alphaMode: .mask, alphaCutoff: .nan, isDoubleSided: true), modelIndex: nil,
                componentIndex: nil),
            SourceBakedTriangle(
                packedUVs: badUv, tangent: first.tangent, policy: first.policy, modelIndex: nil, componentIndex: nil),
            SourceBakedTriangle(
                packedUVs: nil, tangent: first.tangent, policy: first.policy, modelIndex: nil, componentIndex: nil),
        ]
        for record in badRecords {
            var records = base.triangles
            records[0] = record
            XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: replacing(base, triangles: records)))
        }
        for (error, message) in [
            (TexturedRenderGeometryError.invalidSourceMetadata, "source"), (.invalidSamplingLod, "LOD"),
        ] {
            XCTAssertTrue(error.localizedDescription.contains(message))
        }
    }

    func testKeepsModelSeamsAndExactIdentityCatalogsWithBoundedGpuArrays() throws {
        let base = try sourceQuad(policy: nil)
        let models = try ["é", "e\u{301}"].map { try ImportedSurfaceIdentity(rawValue: $0) }
        let records = base.triangles.enumerated().map { index, value in
            SourceBakedTriangle(
                packedUVs: value.packedUVs, tangent: value.tangent, policy: value.policy,
                modelIndex: index, componentIndex: nil)
        }
        let source = replacing(base, triangles: records, models: models)
        let geometry = try TexturedRenderGeometry(bakedMesh: source)
        XCTAssertEqual(geometry.vertices.count, 6, "Distinct model memberships must prevent cross-model corner sharing")
        let bytes =
            geometry.vertices.count * MemoryLayout<TexturedRenderGeometry.Vertex>.stride + geometry.indices.count
            * MemoryLayout<UInt32>.stride
        XCTAssertNoThrow(try TexturedRenderGeometry(bakedMesh: source, maximumPayloadBytes: bytes))
        XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: source, maximumPayloadBytes: bytes - 1))
        guard case .source(_, let copied, _) = geometry.metadata else { return XCTFail("Missing exact source catalog") }
        XCTAssertEqual(copied, models)
        XCTAssertEqual(geometry.maximumSamplingLod, 0)
    }

    func testBoundsPolicyDrawRunsWhileAllowingExactLimit() throws {
        let base = try sourceQuad(policy: nil)
        for pairs in [2048, 2049] {
            let vertices = Array(repeating: base.geometry.vertices, count: pairs).flatMap { $0 }
            let triangles = (0..<pairs * 2).map { index in
                let value = base.triangles[index % 2]
                return SourceBakedTriangle(
                    packedUVs: value.packedUVs, tangent: value.tangent,
                    policy: .init(
                        alphaMode: index.isMultiple(of: 2) ? .opaque : .mask, alphaCutoff: 0.5, isDoubleSided: true),
                    modelIndex: nil, componentIndex: nil)
            }
            let mesh = Mesh(vertices: vertices, nodeCount: 0, partCount: 0, warning: "")
            let geometry = try TexturedRenderGeometry(bakedMesh: replacing(base, mesh: mesh, triangles: triangles))
            if pairs == 2048 {
                XCTAssertEqual(
                    try BakedTriangleOrder(geometry: geometry, hasTransparentColor: true).opaqueBatches.count, 4096)
            } else {
                XCTAssertThrowsError(try BakedTriangleOrder(geometry: geometry, hasTransparentColor: true)) {
                    XCTAssertEqual($0 as? BakedMetalPreparationError, .drawLimitExceeded)
                }
            }
        }
    }

    func testRoutesOpaqueAndMaskedSourcesToDepthWritingPassAndBlendToSortedPass() throws {
        for mode in [ImportedAlphaMode.opaque, .mask, .blend] {
            let policy = SourceBakedPolicy(alphaMode: mode, alphaCutoff: 0.5, isDoubleSided: false)
            let geometry = try TexturedRenderGeometry(bakedMesh: sourceQuad(policy: policy))
            let order = try BakedTriangleOrder(geometry: geometry, hasTransparentColor: mode != .blend)
            XCTAssertEqual(order.opaqueIndices.count, mode == .blend ? 0 : 6)
            XCTAssertEqual(order.transparentIndexCount, mode == .blend ? 6 : 0)
        }
    }
    func testPreparesActualImportedBakeWithoutInventingLegacyChartsOrDroppingPolicy() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/ImportedSurface.ds3")
        let archive = try Data(contentsOf: url)
        let baked = try await ArchiveSourceTextureBakingService().load(
            data: archive,
            options: SourceMeshBakeOptions(
                bake: MeshBakeOptions(colorSize: 256, normalSize: 128, materialSize: 256, atlasTextureSize: 256)))
        let geometry = try TexturedRenderGeometry(bakedMesh: baked)
        XCTAssertEqual(geometry.indices.count, baked.geometry.vertices.count)
        XCTAssertEqual(geometry.maximumSamplingLod, baked.maximumSamplingLod)
        XCTAssertEqual(geometry.textures.color, baked.textures.color)
        guard case .source(let triangles, let models, let components) = geometry.metadata else {
            return XCTFail("Source metadata must not be replaced by fabricated legacy charts")
        }
        XCTAssertEqual(triangles, baked.triangles)
        XCTAssertEqual(models, baked.modelIDs)
        XCTAssertEqual(components, baked.components)
    }

    private func sourceQuad(policy: SourceBakedPolicy?) throws -> SourceBakedMesh {
        let legacy = try BakedMetalFixture.quad(color: BakedMetalFixture.image([255, 0, 0, 128]))
        return BakedMetalFixture.source(legacy, policy: policy)
    }

    private func replacing(
        _ value: SourceBakedMesh, mesh: Mesh? = nil, triangles: [SourceBakedTriangle]? = nil,
        models: [ImportedSurfaceIdentity]? = nil, components: [ImportedSurfaceComponent]? = nil,
        textures: MeshTextureMaps? = nil, lod: Double? = nil
    ) -> SourceBakedMesh {
        SourceBakedMesh(
            geometry: mesh ?? value.geometry, triangles: triangles ?? value.triangles,
            modelIDs: models ?? value.modelIDs, components: components ?? value.components,
            textures: textures ?? value.textures,
            maximumSamplingLod: lod ?? value.maximumSamplingLod, nativePayloadBytes: value.nativePayloadBytes,
            copiedPayloadBytes: value.copiedPayloadBytes)
    }
}
