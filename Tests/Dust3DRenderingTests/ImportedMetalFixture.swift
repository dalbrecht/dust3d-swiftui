import Foundation
import simd

@testable import Dust3DKit

/// Independent post-decode inputs for the production imported renderer, not image baselines.
enum ImportedMetalFixture {
    struct Layer {
        let depth: Float
        let pixels: [UInt8]
        let width: Int
        let height: Int
        init(depth: Float = 0, rgba: [UInt8] = [255, 255, 255, 255]) {
            self.depth = depth
            width = 2
            height = 2
            pixels = Array(repeating: rgba, count: 4).flatMap { $0 }
        }
        init(depth: Float = 0, pixels: [UInt8], width: Int = 2, height: Int = 2) {
            self.depth = depth
            self.pixels = pixels
            self.width = width
            self.height = height
        }
    }

    static func quad(
        mode: ImportedAlphaMode = .opaque, baseColor: SIMD4<Double> = SIMD4(repeating: 1),
        color: SIMD4<Double> = SIMD4(repeating: 1), cutoff: Double = 0.5,
        metallic: Double = 0, roughness: Double = 1, emissive: SIMD3<Double> = .zero,
        doubleSided: Bool = false, reversed: Bool = false, hasImage: Bool = true,
        sampler: ImportedTextureSampler? = nil, sample: SIMD2<Double>? = nil,
        layers: [Layer] = [Layer()]
    ) throws -> ImportedMaterialRenderData {
        let source = try importedRenderFixture()
        let encoded = source.materials[0].definition.image
        var vertices: [MeshVertex] = []
        var triangles: [ImportedSurfaceTriangle] = []
        var materials: [ImportedRenderMaterial] = []
        let coordinates = [SIMD2<Double>(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 0), SIMD2(0, 0)]
        for (index, layer) in layers.enumerated() {
            let key = try ImportedSurfaceIdentity(rawValue: "layer-\(index)")
            let positions = [
                SIMD3<Float>(-1, -1, layer.depth), SIMD3(1, -1, layer.depth), SIMD3(1, 1, layer.depth),
                SIMD3(-1, -1, layer.depth), SIMD3(1, 1, layer.depth), SIMD3(-1, 1, layer.depth),
            ]
            for start in [0, 3] {
                let corners = reversed ? [start, start + 2, start + 1] : [start, start + 1, start + 2]
                for corner in corners {
                    vertices.append(
                        MeshVertex(position: positions[corner], normal: SIMD3(0, 0, 1), color: SIMD4(repeating: 1)))
                }
                let uv = MeshUvCorners(
                    first: sample ?? coordinates[corners[0]], second: sample ?? coordinates[corners[1]],
                    third: sample ?? coordinates[corners[2]])
                triangles.append(
                    ImportedSurfaceTriangle(
                        sourceUVs: uv, colors: ImportedSurfaceColors(first: color, second: color, third: color),
                        colorEncoding: .linear, modelIndex: index, componentIndex: 0))
            }
            let policy =
                sampler
                ?? ImportedTextureSampler(
                    magnification: .nearest, minification: .nearest, wrapS: .clampToEdge, wrapT: .clampToEdge)
            let definition = ImportedModelMaterial(
                id: key.rawValue, baseColor: baseColor, metallic: metallic, roughness: roughness, emissive: emissive,
                alphaMode: mode, alphaCutoff: cutoff, isDoubleSided: doubleSided, sampler: hasImage ? policy : nil,
                image: hasImage ? encoded : nil)
            materials.append(
                ImportedRenderMaterial(
                    id: key, definition: definition,
                    image: hasImage
                        ? ImportedDecodedImage(
                            modelID: key.rawValue, width: layer.width, height: layer.height, rowStride: layer.width * 4,
                            pixels: Data(layer.pixels)) : nil)
            )
        }
        let surface = ImportedSurfaceMesh(
            mesh: Mesh(vertices: vertices, nodeCount: layers.count, partCount: layers.count, warning: ""),
            triangles: triangles, modelIDs: materials.map(\.id), components: source.surface.components,
            nativePayloadBytes: 4096, copiedPayloadBytes: 4096)
        return ImportedMaterialRenderData(
            surface: surface, materials: materials,
            decodedPayloadBytes: hasImage ? layers.reduce(0, { $0 + $1.pixels.count }) : 0)
    }
}
