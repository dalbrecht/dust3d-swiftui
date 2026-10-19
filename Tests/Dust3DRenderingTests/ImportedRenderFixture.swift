import Foundation
import simd

@testable import Dust3DKit

func importedRenderFixture(
    modes: [ImportedAlphaMode] = [.opaque], triangleMaterials: [Int?] = [0], depths: [Float] = [0],
    encoding: ImportedSurfaceColorEncoding = .linear,
    color: SIMD4<Double> = SIMD4(0.5, 0.25, 0.75, 0.4), hasImage: Bool = true,
    minification: ImportedMinificationFilter = .nearestMipmapNearest
) throws -> ImportedMaterialRenderData {
    let keys = try modes.indices.map { try ImportedSurfaceIdentity(rawValue: "model-\($0)") }
    let png = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Dust3DKitTests/Fixtures/ImportedMaterial.png")
    let encoded = try Data(contentsOf: png)
    let pixels = Data([255, 0, 0, 128, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 64])
    let sampler = ImportedTextureSampler(
        magnification: .nearest, minification: minification, wrapS: .clampToEdge, wrapT: .mirroredRepeat)
    let materials = modes.enumerated().map { index, mode in
        let definition = ImportedModelMaterial(
            id: keys[index].rawValue, baseColor: SIMD4(0.25, 0.5, 0.75, 0.5), metallic: 0.125, roughness: 0.625,
            emissive: SIMD3(0.1, 0.2, 0.3), alphaMode: mode, alphaCutoff: 0.375, isDoubleSided: false,
            sampler: hasImage ? sampler : nil,
            image: hasImage ? ImportedEncodedImage(encoding: .png, bytes: encoded) : nil)
        return ImportedRenderMaterial(
            id: keys[index], definition: definition,
            image: hasImage
                ? ImportedDecodedImage(modelID: keys[index].rawValue, width: 2, height: 2, rowStride: 8, pixels: pixels)
                : nil)
    }
    var vertices: [MeshVertex] = []
    var triangles: [ImportedSurfaceTriangle] = []
    for (ordinal, material) in triangleMaterials.enumerated() {
        let depth = depths[ordinal]
        for point in [SIMD3<Float>(-0.8, -0.8, depth), SIMD3(0.8, -0.8, depth), SIMD3(0, 0.8, depth)] {
            vertices.append(MeshVertex(position: point, normal: SIMD3(0, 0, 1), color: SIMD4(1, 1, 1, 1)))
        }
        let uv =
            material == nil ? nil : MeshUvCorners(first: SIMD2(-0.25, 1.25), second: SIMD2(1, 0), third: SIMD2(0, 1))
        triangles.append(
            ImportedSurfaceTriangle(
                sourceUVs: uv, colors: ImportedSurfaceColors(first: color, second: color, third: color),
                colorEncoding: encoding, modelIndex: material, componentIndex: 0))
    }
    let surface = ImportedSurfaceMesh(
        mesh: Mesh(vertices: vertices, nodeCount: 2, partCount: modes.count, warning: ""), triangles: triangles,
        modelIDs: keys,
        components: [ImportedSurfaceComponent(id: try ImportedSurfaceIdentity(rawValue: "component"), kind: .original)],
        nativePayloadBytes: 4096, copiedPayloadBytes: 4096)
    return ImportedMaterialRenderData(
        surface: surface, materials: materials, decodedPayloadBytes: hasImage ? modes.count * 16 : 0)
}
