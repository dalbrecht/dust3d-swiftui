import Foundation

/// Off-main-actor persistence. Savepoint ownership stays with the calling document session.
public actor DocumentFileService {
    public init() {}

    /// Read a bounded archive, retaining file-system diagnostics and checking cancellation.
    public func load(from url: URL) throws -> Dust3DDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 256 * 1024 * 1024 + 1) ?? Data()
        try Task.checkCancellation()
        let document = try Dust3DDocument(data: data)
        try Task.checkCancellation()
        return document
    }

    /// Atomically replace a file. Only mark history saved after this call succeeds.
    public func save(_ document: Dust3DDocument, to url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        try document.encoded().write(to: url, options: .atomic)
    }
}
