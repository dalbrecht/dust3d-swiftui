import Foundation
import Metal
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

final class SourceMipRoutingTests: XCTestCase {
    func testMapsOwnedRolesToCanonicalSlotsWithoutInventingMissingChains() throws {
        XCTAssertTrue(SourceBakedMipmaps().materialUploadSlots.isEmpty)
        let chains = try (0..<5).map { value in
            try TextureMipChain(
                levels: [
                    image(side: 2, rgba: [UInt8(value), 0, 0, 255]), image(side: 1, rgba: [UInt8(value), 0, 0, 255]),
                ],
                maximumSamplingLod: 1)
        }
        let maps = SourceBakedMipmaps(
            color: chains[0], normal: chains[1], metallic: chains[2], roughness: chains[3], emissive: chains[4])
        XCTAssertEqual(
            maps.materialUploadSlots,
            Dictionary(uniqueKeysWithValues: chains.enumerated().map { ($0.offset, $0.element) }))
        XCTAssertEqual(
            SourceBakedMipmaps(normal: chains[1], roughness: chains[3]).materialUploadSlots,
            [1: chains[1], 3: chains[3]])
    }

    @MainActor
    func testPublicFilePreviewUsesOwnedSourceMipsAndRetainsMissingChainFailure() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device is available") }
        let color = image(side: 512, rgba: [255, 0, 0, 255])
        let baked = try BakedMetalFixture.quad(color: color)
        let base = BakedMetalFixture.source(
            baked, policy: .init(alphaMode: .opaque, alphaCutoff: 0.5, isDoubleSided: true))
        let chain = try TextureMipChain(
            levels: [color, image(side: 256, rgba: [0, 255, 0, 255]), image(side: 128, rgba: [0, 0, 255, 255])],
            maximumSamplingLod: 2)
        let ordinary = IndexedMesh(
            vertices: base.geometry.vertices, indices: base.geometry.vertices.indices.map { UInt32($0) }, nodeCount: 0,
            partCount: 0, warning: "")
        for retainsMips in [true, false] {
            let source = SourceBakedMesh(
                geometry: base.geometry, triangles: base.triangles, modelIDs: [], components: [],
                textures: base.textures, mipmaps: SourceBakedMipmaps(color: retainsMips ? chain : nil),
                maximumSamplingLod: 2, nativePayloadBytes: 0, copiedPayloadBytes: 0)
            let document = FilePreviewDocument(mesh: ordinary, materials: .sourceBaked(source), materialError: nil)
            let result = try await FilePreviewRenderer.render(
                document: document, maximumSize: CGSize(width: 128, height: 128), scale: 1)
            let center = (64 * result.image.rowStride) + 64 * 4
            XCTAssertEqual(result.image.pixels[center + 3], 255)
            if retainsMips {
                XCTAssertNil(result.materialError)
                XCTAssertGreaterThan(
                    Int(result.image.pixels[center]), Int(result.image.pixels[center + 2]) + 50,
                    "BGRA preview readback must show the retained blue mip")
            } else {
                XCTAssertEqual(
                    result.materialError as? BakedMetalPreparationError, .invalidTexture("color missing mip chain"))
            }
        }
    }

    private func image(side: Int, rgba: [UInt8]) -> MeshTextureImage {
        BakedMetalFixture.image(Array(repeating: rgba, count: side * side).flatMap { $0 }, width: side, height: side)
    }
}
