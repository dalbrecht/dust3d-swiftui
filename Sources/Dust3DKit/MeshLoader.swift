import Dust3DEngine
import Foundation

/// Errors returned by the native engine, with the original diagnostic preserved.
public struct MeshLoadingError: LocalizedError, Sendable {
    public let status: UInt32
    public let message: String

    public var errorDescription: String? { message }
}

/// Loads immutable meshes. The C bridge serializes access to inherited engine globals.
public enum MeshLoader {
    /// Generate optional preview geometry, distinguishing a successful empty result from failure.
    /// - Parameter data: Complete `.ds3` archive bytes.
    /// - Returns: Copied nonempty geometry, or nil only when the core explicitly reports successful no-geometry.
    /// - Throws: `MeshLoadingError` for all other failures, preserving the original status and diagnostic.
    /// - Example: `let mesh = try MeshLoader.loadIfPresent(data: archive)`.
    public static func loadIfPresent(data: Data) throws -> Mesh? {
        do {
            return try load(data: data)
        } catch let error as MeshLoadingError where error.status == DUST3D_STATUS_NO_GEOMETRY.rawValue {
            return nil
        }
    }

    public static let maximumFileSize = 256 * 1024 * 1024

    /// Generate a mesh from a complete Dust3D archive.
    /// - Parameter data: The bytes of an existing `.ds3` document.
    /// - Returns: Copied geometry, counts, and compatibility warnings.
    /// - Throws: `MeshLoadingError` for malformed/unsupported documents, generation failures or a no-geometry result.
    /// Use `loadIfPresent(data:)` when successful emptiness should return nil.
    public static func load(data: Data) throws -> Mesh {
        try withNativeMesh(data: data) { handle in
            let count = Int(dust3d_mesh_vertex_count(handle))
            guard let source = dust3d_mesh_vertices(handle), count > 0 else {
                throw MeshLoadingError(status: 3, message: "The engine returned an empty mesh.")
            }
            return Mesh(
                vertices: UnsafeBufferPointer(start: source, count: count).map(copyVertex),
                nodeCount: Int(dust3d_mesh_node_count(handle)),
                partCount: Int(dust3d_mesh_part_count(handle)),
                warning: String(cString: dust3d_mesh_warning(handle))
            )
        }
    }

    /// Generate independently owned indexed geometry, copying every native buffer into Swift.
    /// - Parameters:
    ///   - data: Complete `.ds3` archive bytes.
    ///   - maximumPayloadBytes: Limit for native vertex and index payloads; zero uses the core's
    ///     256 MiB default. Excludes generation, deduplication workspace, and Swift copies.
    /// - Returns: Immutable vertices, triangle indices, source counts, and compatibility warnings.
    /// - Throws: `MeshLoadingError` for negative budgets, malformed input, generation failures,
    ///   successful no-geometry, or an insufficient payload budget. Native diagnostics are preserved.
    /// - Example: `let mesh = try MeshLoader.loadIndexed(data: archive)`.
    public static func loadIndexed(data: Data, maximumPayloadBytes: Int = 0) throws -> IndexedMesh {
        guard maximumPayloadBytes >= 0 else {
            throw MeshLoadingError(status: 1, message: "The maximum payload budget must be zero or positive.")
        }
        // Release the expanded native source before allocating the Swift copies.
        let handle = try withNativeMesh(data: data) { source in
            var error = Dust3DError()
            guard let indexed = dust3d_mesh_create_indexed(source, maximumPayloadBytes, &error) else {
                throw loadingError(error)
            }
            return indexed
        }
        defer { dust3d_indexed_mesh_destroy(handle) }
        let vertexCount = Int(dust3d_indexed_mesh_vertex_count(handle))
        let indexCount = Int(dust3d_indexed_mesh_index_count(handle))
        guard let vertices = dust3d_indexed_mesh_vertices(handle),
            let indices = dust3d_indexed_mesh_indices(handle),
            vertexCount > 0, indexCount > 0, indexCount.isMultiple(of: 3)
        else {
            throw MeshLoadingError(status: 3, message: "The engine returned invalid indexed mesh buffers.")
        }
        return IndexedMesh(
            vertices: UnsafeBufferPointer(start: vertices, count: vertexCount).map(copyVertex),
            indices: Array(UnsafeBufferPointer(start: indices, count: indexCount)),
            nodeCount: Int(dust3d_indexed_mesh_node_count(handle)),
            partCount: Int(dust3d_indexed_mesh_part_count(handle)),
            warning: String(cString: dust3d_indexed_mesh_warning(handle))
        )
    }

    /// Generate an indexed preview, returning nil only for explicit successful no-geometry.
    /// - Parameters:
    ///   - data: Complete `.ds3` archive bytes.
    ///   - maximumPayloadBytes: Native payload budget, with the same semantics as `loadIndexed`.
    /// - Returns: Copied indexed geometry, or nil when the core reports no geometry.
    /// - Throws: All other `MeshLoadingError` values with their original diagnostics.
    /// - Example: `let preview = try MeshLoader.loadIndexedIfPresent(data: archive)`.
    public static func loadIndexedIfPresent(data: Data, maximumPayloadBytes: Int = 0) throws -> IndexedMesh? {
        do {
            return try loadIndexed(data: data, maximumPayloadBytes: maximumPayloadBytes)
        } catch let error as MeshLoadingError where error.status == DUST3D_STATUS_NO_GEOMETRY.rawValue {
            return nil
        }
    }

    private static func withNativeMesh<Output>(data: Data, operation: (OpaquePointer) throws -> Output) throws -> Output
    {
        var error = Dust3DError()
        let handle = data.withUnsafeBytes { bytes in
            dust3d_mesh_load(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &error)
        }
        guard let handle else { throw loadingError(error) }
        defer { dust3d_mesh_destroy(handle) }
        return try operation(handle)
    }

    private static func loadingError(_ error: Dust3DError) -> MeshLoadingError {
        var error = error
        let message = withUnsafeBytes(of: &error.message) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return MeshLoadingError(status: error.status.rawValue, message: message)
    }

    private static func copyVertex(_ vertex: Dust3DVertex) -> MeshVertex {
        MeshVertex(
            position: SIMD3(vertex.position.0, vertex.position.1, vertex.position.2),
            normal: SIMD3(vertex.normal.0, vertex.normal.1, vertex.normal.2),
            color: SIMD4(vertex.color.0, vertex.color.1, vertex.color.2, vertex.color.3)
        )
    }
}
