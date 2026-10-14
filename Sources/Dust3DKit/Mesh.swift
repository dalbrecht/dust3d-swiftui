import simd

/// A copied triangle vertex. No C++ memory escapes into Swift.
public struct MeshVertex: Sendable {
    public let position: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let color: SIMD4<Float>
}

/// Immutable mesh data shared between the background loader and the renderer.
public struct Mesh: Sendable {
    public let vertices: [MeshVertex]
    public let nodeCount: Int
    public let partCount: Int
    public let warning: String

    public var triangleCount: Int { vertices.count / 3 }
}
