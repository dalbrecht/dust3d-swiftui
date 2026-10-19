import Foundation
import simd

@testable import Dust3DKit

/// Independent geometry and RGBA samples for production Metal tests, not rendered baselines.
enum BakedMetalFixture {
    static func source(_ mesh: MeshWithBakedTextures, policy: SourceBakedPolicy?) -> SourceBakedMesh {
        source(mesh, policyAt: { _ in policy })
    }

    static func source(_ mesh: MeshWithBakedTextures, policyAt: (Int) -> SourceBakedPolicy?) -> SourceBakedMesh {
        let records = mesh.metadata.triangles.enumerated().map { index, triangle in
            SourceBakedTriangle(
                packedUVs: triangle.hasMapping ? triangle.corners : nil,
                tangent: mesh.tangents[index], policy: policyAt(index), modelIndex: nil, componentIndex: nil)
        }
        return SourceBakedMesh(
            geometry: mesh.geometry, triangles: records, modelIDs: [], components: [],
            textures: mesh.textures, maximumSamplingLod: 0, nativePayloadBytes: 0, copiedPayloadBytes: 0)
    }

    struct Layer {
        let depth: Float
        let sample: SIMD2<Double>?
        let color: SIMD4<Float>
        init(depth: Float = 0, sample: SIMD2<Double>? = nil, color: SIMD4<Float> = SIMD4(1, 1, 1, 1)) {
            self.depth = depth
            self.sample = sample
            self.color = color
        }
    }

    static func image(_ rgba: [UInt8], width: Int = 1, height: Int = 1) -> MeshTextureImage {
        MeshTextureImage(width: width, height: height, rowStride: width * 4, pixels: Data(rgba))
    }

    static func quad(
        color: MeshTextureImage? = nil, normal: MeshTextureImage? = nil, metallic: MeshTextureImage? = nil,
        roughness: MeshTextureImage? = nil, emissive: MeshTextureImage? = nil,
        mapped: Bool = true, tangentMapped: Bool = true, handedness: Float = 1,
        layers: [Layer] = [Layer()]
    ) throws -> MeshWithBakedTextures {
        var vertices: [MeshVertex] = []
        var triangles: [RawMeshUvTriangle] = []
        var tangents: [MeshTextureTangent] = []
        var charts: [RawMeshUvChart] = []
        let identifiers = layers.indices.map { String(format: "{00000000-0000-4000-8000-%012d}", $0 + 1) }
        let coordinates: [SIMD2<Double>] = [
            SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 0), SIMD2(0, 0),
        ]
        for (index, layer) in layers.enumerated() {
            let positions: [SIMD3<Float>] = [
                SIMD3(-1, -1, layer.depth), SIMD3(1, -1, layer.depth), SIMD3(1, 1, layer.depth),
                SIMD3(-1, -1, layer.depth), SIMD3(1, 1, layer.depth), SIMD3(-1, 1, layer.depth),
            ]
            vertices += positions.map { MeshVertex(position: $0, normal: SIMD3(0, 0, 1), color: layer.color) }
            for start in [0, 3] {
                func uv(_ corner: Int) -> SIMD2<Double> {
                    mapped ? (layer.sample ?? coordinates[start + corner]) : .zero
                }
                triangles.append(
                    RawMeshUvTriangle(
                        corners: MeshUvCorners(first: uv(0), second: uv(1), third: uv(2)), known: mapped ? 1 : 0,
                        componentKind: 1, componentIndex: index))
                tangents.append(
                    MeshTextureTangent(
                        direction: SIMD3(1, 0, 0), handedness: handedness, hasMapping: mapped && tangentMapped))
            }
            charts.append(
                RawMeshUvChart(
                    origin: .zero, size: SIMD2(1, 1), color: SIMD4(1, 1, 1, 1), flipped: 0, componentKind: 1,
                    componentIndex: index, imageID: nil))
        }
        let metadata = try MeshUvMetadata(
            componentIDs: identifiers, triangles: triangles, charts: charts, gradients: [],
            expandedVertexCount: vertices.count, packedTextureSize: 8)
        return MeshWithBakedTextures(
            geometry: Mesh(vertices: vertices, nodeCount: layers.count, partCount: layers.count, warning: ""),
            metadata: metadata, tangents: tangents,
            textures: MeshTextureMaps(
                color: color ?? image([255, 255, 255, 255]), normal: normal, metallic: metallic, roughness: roughness,
                emissive: emissive))
    }
}
