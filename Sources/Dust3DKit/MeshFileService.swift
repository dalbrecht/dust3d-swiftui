import Foundation

/// Copied archive and geometry from one bounded read, preventing cross-read material races.
public struct MeshFileSnapshot: Sendable {
    public let data: Data
    public let mesh: IndexedMesh
    /// Derived from the same immutable archive off-main; interpretation failure never hides its cause.
    public let materialSourceCapabilities: MaterialSourceCapabilities

    init(data: Data, mesh: IndexedMesh, materialSourceCapabilities: MaterialSourceCapabilities = .unknown) {
        self.data = data
        self.mesh = mesh
        self.materialSourceCapabilities = materialSourceCapabilities
    }
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
        let capabilities = MaterialSourceCapabilities.read(data: data)
        try Task.checkCancellation()
        return MeshFileSnapshot(data: data, mesh: mesh, materialSourceCapabilities: capabilities)
    }

    /// Read immutable archive bytes for constrained system preview workers without generating geometry.
    /// - Parameters:
    ///   - url: Local or security-scoped document URL.
    ///   - maximumBytes: Positive allocation ceiling, at most the shared 256 MiB file limit.
    /// - Returns: One owned snapshot of the selected archive.
    /// - Throws: Original filesystem/cancellation errors or `MeshLoadingError` for invalid/excess limits.
    public func readArchive(url: URL, maximumBytes: Int) throws -> Data {
        guard (1...MeshLoader.maximumFileSize).contains(maximumBytes) else {
            throw MeshLoadingError(status: 4, message: "The archive read limit must be positive and at most 256 MiB.")
        }
        return try read(url: url, maximumBytes: maximumBytes)
    }

    private func read(url: URL, maximumBytes: Int = MeshLoader.maximumFileSize) throws -> Data {
        try Task.checkCancellation()
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size <= maximumBytes else {
            throw MeshLoadingError(status: 4, message: "The document exceeds the \(maximumBytes)-byte file limit.")
        }
        try file.seek(toOffset: 0)
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        // Reject growth between the initial size check and the bounded read.
        guard data.count <= maximumBytes else {
            throw MeshLoadingError(status: 4, message: "The document exceeds the \(maximumBytes)-byte file limit.")
        }
        try Task.checkCancellation()
        return data
    }
}
