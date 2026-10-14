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
    public static let maximumFileSize = 256 * 1024 * 1024

    /// Generate a mesh from a complete Dust3D archive.
    /// - Parameter data: The bytes of an existing `.ds3` document.
    /// - Returns: Copied geometry, counts, and compatibility warnings.
    /// - Throws: `MeshLoadingError` for malformed or unsupported documents.
    public static func load(data: Data) throws -> Mesh {
        var error = Dust3DError()
        let handle = data.withUnsafeBytes { bytes in
            dust3d_mesh_load(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &error)
        }
        guard let handle else {
            let message = withUnsafeBytes(of: error.message) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            throw MeshLoadingError(status: error.status.rawValue, message: message)
        }
        defer { dust3d_mesh_destroy(handle) }
        let count = Int(dust3d_mesh_vertex_count(handle))
        guard let source = dust3d_mesh_vertices(handle), count > 0 else {
            throw MeshLoadingError(status: 3, message: "The engine returned an empty mesh.")
        }
        let vertices = UnsafeBufferPointer(start: source, count: count).map { vertex in
            MeshVertex(
                position: SIMD3(vertex.position.0, vertex.position.1, vertex.position.2),
                normal: SIMD3(vertex.normal.0, vertex.normal.1, vertex.normal.2),
                color: SIMD4(vertex.color.0, vertex.color.1, vertex.color.2, vertex.color.3)
            )
        }
        return Mesh(
            vertices: vertices,
            nodeCount: Int(dust3d_mesh_node_count(handle)),
            partCount: Int(dust3d_mesh_part_count(handle)),
            warning: String(cString: dust3d_mesh_warning(handle))
        )
    }
}
