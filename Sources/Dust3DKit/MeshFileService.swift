import Foundation

/// A serial background document service. File access and C++ work stay off the main actor.
public actor MeshFileService {
    public init() {}

    /// Read a selected `.ds3` file with a bounded allocation and generate its geometry.
    /// - Parameter url: A local or security-scoped document URL.
    /// - Throws: File-system errors, cancellation, or `MeshLoadingError`.
    public func load(url: URL) throws -> Mesh {
        let data = try read(url: url)
        let mesh = try MeshLoader.load(data: data)
        try Task.checkCancellation()
        return mesh
    }

    /// Read a bounded `.ds3` file and copy indexed geometry off the UI actor.
    /// - Parameter url: A local or security-scoped document URL.
    /// - Returns: Immutable indexed geometry and copied source metadata.
    /// - Throws: File-system errors, cancellation, or `MeshLoadingError` with native diagnostics.
    /// - Example: `let mesh = try await MeshFileService().loadIndexed(url: file)`.
    public func loadIndexed(url: URL) throws -> IndexedMesh {
        let data = try read(url: url)
        let mesh = try MeshLoader.loadIndexed(data: data)
        try Task.checkCancellation()
        return mesh
    }

    private func read(url: URL) throws -> Data {
        try Task.checkCancellation()
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size <= MeshLoader.maximumFileSize else {
            throw MeshLoadingError(status: 4, message: "The document exceeds the 256 MiB file limit.")
        }
        try file.seek(toOffset: 0)
        let data = try file.read(upToCount: MeshLoader.maximumFileSize + 1) ?? Data()
        try Task.checkCancellation()
        return data
    }
}
