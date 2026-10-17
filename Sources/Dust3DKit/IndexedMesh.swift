/// Immutable indexed triangle geometry. All storage belongs to Swift; no native pointers escape.
public struct IndexedMesh: Sendable {
    /// Unique vertices, preserving position, normal, and color seams.
    public let vertices: [MeshVertex]
    /// Triangle vertex references, grouped in threes and bounded by `vertices.count`.
    public let indices: [UInt32]
    /// Number of source document nodes.
    public let nodeCount: Int
    /// Number of source document parts.
    public let partCount: Int
    /// Compatibility diagnostics copied from the native generator.
    public let warning: String

    /// Number of indexed triangles.
    public var triangleCount: Int { indices.count / 3 }
}
