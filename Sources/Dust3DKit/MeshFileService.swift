import Foundation

/// Copied archive and geometry from one bounded read, preventing cross-read material races.
public struct MeshFileSnapshot: Sendable {
    public let data: Data
    public let mesh: IndexedMesh
}

/// Injectable file snapshot boundary for native viewer lifecycles.
public protocol MeshFileSnapshotLoading: Sendable {
    /// Read one bounded file and generate matching indexed geometry.
    /// - Parameter url: Local or security-scoped document URL.
    /// - Returns: Exact input archive paired with its copied geometry.
    /// - Throws: Original filesystem, cancellation or native loading errors.
    func loadIndexedSnapshot(url: URL) async throws -> MeshFileSnapshot
}

/// A serial background document service. File access and C++ work stay off the main actor.
public actor MeshFileService: MeshFileSnapshotLoading {
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

    /// Read one archive snapshot for both ordinary geometry and subsequent material baking.
    /// - Parameter url: Local or security-scoped document URL.
    /// - Returns: Owned archive bytes and indexed geometry generated from exactly those bytes.
    /// - Throws: Original filesystem, cancellation or native loading errors.
    public func loadIndexedSnapshot(url: URL) throws -> MeshFileSnapshot {
        let data = try read(url: url)
        let mesh = try MeshLoader.loadIndexed(data: data)
        try Task.checkCancellation()
        return MeshFileSnapshot(data: data, mesh: mesh)
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
