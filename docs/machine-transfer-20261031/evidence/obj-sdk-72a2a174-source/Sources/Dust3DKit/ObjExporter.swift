import Dust3DEngine
import Foundation

/// Synchronous native ownership boundary; callers must run CPU generation off the main actor.
public enum ObjExporter {
    /// Generate complete geometry from one archive snapshot and copy geometry-only OBJ bytes.
    /// - Parameters:
    ///   - data: Exact complete `.ds3` bytes, at most 256 MiB.
    ///   - options: Independent source/indexed/native-output/Swift-copy limits.
    /// - Returns: Owned positions/normals/triangles, preserving source axes, units and winding.
    /// - Throws: ObjExportError, original MeshLoadingError or CancellationError.
    /// - Note: Cancellation prevents publication around native phases; native work cannot be preempted.
    /// - Example: `let output = try ObjExporter.encode(data: archive)`.
    public static func encode(data: Data, options: ObjExportOptions = .init()) throws -> ObjExport {
        try Task.checkCancellation()
        try validate(dataCount: data.count, options: options)
        let indexed = try makeIndexed(data: data, options: options)
        let output: OpaquePointer
        let vertexCount: Int
        let triangleCount: Int
        let warning: String
        do {
            defer { dust3d_indexed_mesh_destroy(indexed) }
            try Task.checkCancellation()
            vertexCount = dust3d_indexed_mesh_vertex_count(indexed)
            triangleCount = dust3d_indexed_mesh_index_count(indexed) / 3
            warning = String(cString: dust3d_indexed_mesh_warning(indexed))
            var error = Dust3DError()
            guard let owner = dust3d_indexed_mesh_export_obj(indexed, options.maximumNativeOutputBytes, &error) else {
                throw MeshLoader.loadingError(error)
            }
            output = owner
        }
        defer { dust3d_obj_export_destroy(output) }
        try Task.checkCancellation()
        return try ObjExportCopy.copy(
            count: dust3d_obj_export_byte_count(output), payload: dust3d_obj_export_payload_bytes(output),
            vertices: vertexCount, triangles: triangleCount, warning: warning, options: options
        ) { dust3d_obj_export_bytes(output) }
    }

    static func validate(dataCount: Int, options: ObjExportOptions) throws {
        let ceiling = 256 * 1024 * 1024
        guard dataCount >= 0,
            [
                options.maximumSourcePayloadBytes, options.maximumIndexedPayloadBytes,
                options.maximumNativeOutputBytes,
            ].allSatisfy({ (0...ceiling).contains($0) }),
            (1...ceiling).contains(options.maximumCopiedPayloadBytes)
        else { throw ObjExportError.invalidLimits }
        guard dataCount <= MeshLoader.maximumFileSize else { throw ObjExportError.archiveLimitExceeded }
    }

    private static func makeIndexed(data: Data, options: ObjExportOptions) throws -> OpaquePointer {
        var native = Dust3DImportedSurfaceOptions()
        native.struct_size = MemoryLayout<Dust3DImportedSurfaceOptions>.size
        native.maximum_payload_bytes = options.maximumSourcePayloadBytes
        var error = Dust3DError()
        let source = data.withUnsafeBytes {
            dust3d_imported_surface_mesh_load($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &native, &error)
        }
        guard let source else { throw MeshLoader.loadingError(error) }
        defer { dust3d_imported_surface_mesh_destroy(source) }
        try Task.checkCancellation()
        guard let geometry = dust3d_imported_surface_mesh_geometry(source) else {
            throw ObjExportError.invalidNativeOutput
        }
        return try MeshLoader.makeNativeIndexedMesh(
            from: geometry, maximumPayloadBytes: options.maximumIndexedPayloadBytes)
    }
}

/// Validate metadata before borrowing pixels; the opaque result remains alive throughout the closure.
enum ObjExportCopy {
    static func copy(
        count: Int, payload: Int, vertices: Int, triangles: Int, warning: String,
        options: ObjExportOptions, bytes: () -> UnsafePointer<UInt8>?
    ) throws -> ObjExport {
        try Task.checkCancellation()
        let nativeLimit = options.maximumNativeOutputBytes == 0 ? 256 * 1024 * 1024 : options.maximumNativeOutputBytes
        guard count > 0, payload >= count, payload <= nativeLimit, vertices > 0, triangles > 0 else {
            throw ObjExportError.invalidNativeOutput
        }
        var remaining = options.maximumCopiedPayloadBytes
        for charge in [MemoryLayout<ObjExport>.stride, count, warning.utf8.count + 1] {
            guard charge <= remaining else { throw ObjExportError.copyLimitExceeded }
            remaining -= charge
        }
        guard let borrowed = bytes() else { throw ObjExportError.invalidNativeOutput }
        try Task.checkCancellation()
        let data = Data(bytes: borrowed, count: count)
        try Task.checkCancellation()
        return ObjExport(
            data: data, vertexCount: vertices, triangleCount: triangles, warning: warning,
            nativePayloadBytes: payload, copiedPayloadBytes: options.maximumCopiedPayloadBytes - remaining)
    }
}
