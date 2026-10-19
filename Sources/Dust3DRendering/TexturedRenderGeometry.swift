import Dust3DKit
import Foundation
import simd

/// Preparation failures remain independent of Metal allocation and UI presentation.
enum TexturedRenderGeometryError: LocalizedError, Equatable {
    case invalidLimits
    case invalidGeometry
    case inconsistentTriangles
    case invalidTangent
    case payloadLimitExceeded
    case deviceLimitExceeded
    case invalidSourceMetadata
    case invalidSamplingLod

    var errorDescription: String? {
        switch self {
        case .invalidLimits: return "The textured geometry resource limit is invalid."
        case .invalidGeometry: return "The textured geometry is empty or contains invalid vertices."
        case .inconsistentTriangles:
            return "The textured triangle counts, mapping flags or UV coordinates are inconsistent."
        case .invalidTangent: return "The textured geometry has an invalid tangent frame."
        case .payloadLimitExceeded: return "The textured vertex/index arrays exceed the configured payload limit."
        case .deviceLimitExceeded: return "The textured arrays exceed this Metal device's buffer limit."
        case .invalidSourceMetadata: return "The source-baked catalogs, references or material policy are invalid."
        case .invalidSamplingLod: return "The source-baked atlas LOD or texture dimensions are invalid."
        }
    }
}

/// Immutable background preparation; no GPU objects, document state or native owner escapes.
/// The logical quota covers vertex/index arrays, excluding source storage and indexing workspace.
struct TexturedRenderGeometry: Sendable {
    struct Vertex: Sendable, Equatable {
        let position: SIMD4<Float>
        let normal: SIMD4<Float>
        let color: SIMD4<Float>
        /// XY are atlas UVs; Z/W explicitly mark UV/tangent applicability.
        let textureCoordinate: SIMD4<Float>
        let tangent: SIMD4<Float>
    }

    let vertices: [Vertex]
    let indices: [UInt32]
    let metadata: TexturedRenderMetadata
    let textures: MeshTextureMaps
    let maximumSamplingLod: Double

    /// Prepare off the main actor, preserving source triangle order and all attribute seams.
    /// Identical source bit patterns share deterministically by first occurrence.
    init(bakedMesh: MeshWithBakedTextures, maximumPayloadBytes: Int = 256 * 1024 * 1024) throws {
        try self.init(
            mesh: bakedMesh.geometry, metadata: .legacy(bakedMesh.metadata), textures: bakedMesh.textures,
            tangentCount: bakedMesh.tangents.count, maximumSamplingLod: 0, maximumPayloadBytes: maximumPayloadBytes
        ) { index in
            TexturedInputTriangle(legacy: bakedMesh.metadata.triangles[index], tangent: bakedMesh.tangents[index])
        }
    }

    /// Source-aware bakes retain their exact policy/catalog records and atlas sampling restriction.
    init(bakedMesh: SourceBakedMesh, maximumPayloadBytes: Int = 256 * 1024 * 1024) throws {
        guard Set(bakedMesh.modelIDs).count == bakedMesh.modelIDs.count,
            Set(bakedMesh.components.map(\.id)).count == bakedMesh.components.count
        else {
            throw TexturedRenderGeometryError.invalidSourceMetadata
        }
        let images = [
            bakedMesh.textures.color, bakedMesh.textures.normal, bakedMesh.textures.metallic,
            bakedMesh.textures.roughness, bakedMesh.textures.emissive,
        ].compactMap { $0 }
        guard images.allSatisfy({ (1...8192).contains($0.width) && (1...8192).contains($0.height) }) else {
            throw TexturedRenderGeometryError.invalidSamplingLod
        }
        let minimumDimension = images.reduce(8192) { min($0, min($1.width, $1.height)) }
        guard bakedMesh.maximumSamplingLod.isFinite, bakedMesh.maximumSamplingLod >= 0,
            bakedMesh.maximumSamplingLod <= Double(Int.bitWidth - minimumDimension.leadingZeroBitCount - 1)
        else {
            throw TexturedRenderGeometryError.invalidSamplingLod
        }
        try self.init(
            mesh: bakedMesh.geometry,
            metadata: .source(bakedMesh.triangles, bakedMesh.modelIDs, bakedMesh.components),
            textures: bakedMesh.textures,
            tangentCount: bakedMesh.triangles.count, maximumSamplingLod: bakedMesh.maximumSamplingLod,
            maximumPayloadBytes: maximumPayloadBytes
        ) { index in
            try TexturedInputTriangle(
                source: bakedMesh.triangles[index], models: bakedMesh.modelIDs.count,
                components: bakedMesh.components.count)
        }
    }

    private init(
        mesh: Mesh, metadata: TexturedRenderMetadata, textures: MeshTextureMaps, tangentCount: Int,
        maximumSamplingLod: Double, maximumPayloadBytes: Int,
        triangleAt: (Int) throws -> TexturedInputTriangle
    ) throws {
        guard (1...256 * 1024 * 1024).contains(maximumPayloadBytes) else {
            throw TexturedRenderGeometryError.invalidLimits
        }
        let source = mesh.vertices
        guard !source.isEmpty, source.count.isMultiple(of: 3),
            source.allSatisfy({ vertex in
                (0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite }
                    && (0..<4).allSatisfy { vertex.color[$0].isFinite }
            })
        else { throw TexturedRenderGeometryError.invalidGeometry }
        let triangleCount = source.count / 3
        guard metadata.triangleCount == triangleCount, tangentCount == triangleCount else {
            throw TexturedRenderGeometryError.inconsistentTriangles
        }
        guard source.count <= maximumPayloadBytes / MemoryLayout<UInt32>.stride else {
            throw TexturedRenderGeometryError.payloadLimitExceeded
        }
        let bounds = try RenderBounds(vertices: source)
        var remaining = maximumPayloadBytes - source.count * MemoryLayout<UInt32>.stride
        var vertices: [Vertex] = []
        var indices: [UInt32] = []
        indices.reserveCapacity(source.count)
        var shared: [CornerKey: UInt32] = [:]
        for triangleIndex in 0..<triangleCount {
            try Task.checkCancellation()
            let triangle = try triangleAt(triangleIndex)
            let tangent = triangle.tangent
            let lengthSquared = simd_length_squared(tangent.direction)
            guard (0..<3).allSatisfy({ tangent.direction[$0].isFinite }),
                tangent.handedness == -1 || tangent.handedness == 1,
                !tangent.hasMapping || (triangle.hasMapping && abs(lengthSquared - 1) < 0.0001)
            else { throw TexturedRenderGeometryError.invalidTangent }
            let coordinates = (triangle.corners.first, triangle.corners.second, triangle.corners.third)
            for corner in 0..<3 {
                let uv = corner == 0 ? coordinates.0 : (corner == 1 ? coordinates.1 : coordinates.2)
                guard uv.x.isFinite, uv.y.isFinite, (0...1).contains(uv.x), (0...1).contains(uv.y),
                    triangle.hasMapping || uv == .zero
                else {
                    throw TexturedRenderGeometryError.inconsistentTriangles
                }
                let vertex = source[triangleIndex * 3 + corner]
                let key = CornerKey(vertex: vertex, uv: uv, triangle: triangle, tangent: tangent)
                if let index = shared[key] {
                    indices.append(index)
                    continue
                }
                guard remaining >= MemoryLayout<Vertex>.stride, let index = UInt32(exactly: vertices.count) else {
                    throw TexturedRenderGeometryError.payloadLimitExceeded
                }
                remaining -= MemoryLayout<Vertex>.stride
                vertices.append(
                    Vertex(
                        position: SIMD4((vertex.position - bounds.center) / bounds.radius, 1),
                        normal: SIMD4(vertex.normal, 0), color: vertex.color,
                        textureCoordinate: SIMD4(
                            Float(uv.x), Float(uv.y), triangle.hasMapping ? 1 : 0, tangent.hasMapping ? 1 : 0),
                        tangent: SIMD4(tangent.direction, tangent.handedness)))
                shared[key] = index
                indices.append(index)
            }
        }
        self.vertices = vertices
        self.indices = indices
        self.metadata = metadata
        self.textures = textures
        self.maximumSamplingLod = maximumSamplingLod
    }

    /// Validate both actual GPU-layout array lengths before any device upload.
    func validateBufferLengths(maximumBufferLength: Int) throws {
        guard maximumBufferLength >= 0,
            vertices.count <= maximumBufferLength / MemoryLayout<Vertex>.stride,
            indices.count <= maximumBufferLength / MemoryLayout<UInt32>.stride
        else { throw TexturedRenderGeometryError.deviceLimitExceeded }
    }
}

private struct CornerKey: Hashable {
    let position: SIMD3<UInt32>
    let normal: SIMD3<UInt32>
    let color: SIMD4<UInt32>
    let uv: SIMD2<UInt64>
    let tangent: SIMD4<UInt32>
    let mapping: UInt8
    let componentKind: UInt32
    let componentIndex: Int?
    let modelIndex: Int?

    init(vertex: MeshVertex, uv: SIMD2<Double>, triangle: TexturedInputTriangle, tangent: MeshTextureTangent) {
        position = SIMD3(vertex.position.x.bitPattern, vertex.position.y.bitPattern, vertex.position.z.bitPattern)
        normal = SIMD3(vertex.normal.x.bitPattern, vertex.normal.y.bitPattern, vertex.normal.z.bitPattern)
        color = SIMD4(
            vertex.color.x.bitPattern, vertex.color.y.bitPattern, vertex.color.z.bitPattern, vertex.color.w.bitPattern)
        self.uv = SIMD2(uv.x.bitPattern, uv.y.bitPattern)
        self.tangent = SIMD4(
            tangent.direction.x.bitPattern, tangent.direction.y.bitPattern, tangent.direction.z.bitPattern,
            tangent.handedness.bitPattern)
        mapping = (triangle.hasMapping ? 1 : 0) | (tangent.hasMapping ? 2 : 0)
        componentKind = triangle.componentKind
        componentIndex = triangle.componentIndex
        modelIndex = triangle.modelIndex
    }
}
