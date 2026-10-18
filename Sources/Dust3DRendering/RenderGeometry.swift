import Dust3DKit
import simd

/// Compatibility input; the native apps supply indexed values while expanded SDK callers retain their API.
enum RenderMesh {
    case expanded(Mesh)
    case indexed(IndexedMesh)

    var vertices: [MeshVertex] {
        switch self {
        case .expanded(let mesh): mesh.vertices
        case .indexed(let mesh): mesh.vertices
        }
    }

    var indices: [UInt32]? {
        switch self {
        case .expanded: nil
        case .indexed(let mesh): mesh.indices
        }
    }
}

/// Pure preparation keeps normalization, triangle validation, and GPU layout independent of Metal allocation.
struct RenderGeometry: Sendable {
    struct Vertex: Sendable {
        let position: SIMD4<Float>
        let normal: SIMD4<Float>
        let color: SIMD4<Float>
    }

    let vertices: [Vertex]
    let indices: [UInt32]?

    /// Metal's per-buffer limit differs from the core's combined exported-payload budget.
    func validateBufferLengths(maximumBufferLength: Int) throws {
        guard maximumBufferLength >= 0,
            vertices.count <= maximumBufferLength / MemoryLayout<Vertex>.stride,
            indices.map({ $0.count <= maximumBufferLength / MemoryLayout<UInt32>.stride }) ?? true
        else { throw RendererError.unavailable("The mesh exceeds this Metal device's buffer size limit.") }
    }

    init(mesh: RenderMesh) throws {
        let source = mesh.vertices
        let indices = mesh.indices
        guard !source.isEmpty,
            source.allSatisfy({ vertex in
                (0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite }
                    && (0..<4).allSatisfy { vertex.color[$0].isFinite }
            }),
            indices.map({ !$0.isEmpty && $0.count.isMultiple(of: 3) && $0.allSatisfy { Int($0) < source.count } })
                ?? source.count.isMultiple(of: 3)
        else { throw RendererError.unavailable("The mesh contains invalid triangle buffers.") }
        let bounds = try RenderBounds(vertices: source)
        vertices = source.map { vertex in
            Vertex(
                position: SIMD4((vertex.position - bounds.center) / bounds.radius, 1),
                normal: SIMD4(vertex.normal, 0), color: vertex.color)
        }
        self.indices = indices
    }
}

/// Shared normalization keeps ordinary and textured previews in the same camera space.
struct RenderBounds: Sendable {
    let center: SIMD3<Float>
    let radius: Float

    init(vertices: [MeshVertex]) throws {
        let minimum = vertices.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1.position) }
        let maximum = vertices.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1.position) }
        center = (minimum + maximum) * 0.5
        radius = max(simd_length(maximum - minimum) * 0.5, 0.001)
        guard radius.isFinite, (0..<3).allSatisfy({ center[$0].isFinite }) else {
            throw RendererError.unavailable("The mesh bounds cannot be represented for rendering.")
        }
    }
}

/// Typed preparation/allocation failures; localized presentation stays at the platform boundary.
enum RendererError: Error {
    case unavailable(String)
}
