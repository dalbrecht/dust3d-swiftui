import Dust3DDocument
import Foundation

/// Formats supported by the original-geometry export boundary; no imported/rigged paths implied.
public enum DocumentExportFormat: String, Sendable { case obj, fbx }

/// Owned output copied by the native adapter before releasing its C handle.
public struct DocumentExportArtifact: Sendable, Equatable {
    public let bytes: Data
    public let warning: String

    /// Keep the original export diagnostic beside immutable bytes.
    public init(bytes: Data, warning: String) {
        self.bytes = bytes
        self.warning = warning
    }
}

/// Off-main native encoding boundary. Production binding requires a reviewed core revision.
public protocol DocumentExportEncoding: Sendable {
    /// Encode exactly the supplied archive snapshot; never reread a source path.
    /// - Parameters: archive is the current document's owned encoded state; format selects output geometry.
    /// - Returns: Copied immutable output and original diagnostic.
    /// - Throws: Original native or cancellation error. Implementations must serialize inherited generation.
    func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact
}

/// Typed destination/output admission errors; filesystem and encoder causes propagate unchanged.
public enum DocumentExportError: Error, Sendable, Equatable {
    case invalidDestination, sourceAlias, invalidOutput
}

/// Off-main export publication, independent of the document's savepoint and undo history.
public actor DocumentExportFileService {
    private let encoder: any DocumentExportEncoding
    private static let maximumBytes = 256 * 1024 * 1024

    /// Inject the reviewed native encoder; no fallback preview-based encoder is installed.
    public init(encoder: any DocumentExportEncoding) { self.encoder = encoder }

    /// Encode a captured current document and atomically replace a distinct output file.
    /// - Parameters:
    ///   - document: Immutable current state, including unsaved edits.
    ///   - format: Geometry format matching the destination extension.
    ///   - destination: Local or security-scoped output URL.
    ///   - sourceURL: Current source URL when available, protected against path/inode aliases.
    ///   - validateSnapshot: Optional current-document admission before encoding and before publication.
    ///     Omit for intentionally fixed snapshots. Original admission errors propagate unchanged.
    ///   - publish: Trusted coordinator that executes the supplied synchronous commit exactly once or throws.
    ///     The editor binds it to `EditorSession.publishExport`; the default publishes a fixed snapshot.
    /// - Returns: Published owned output with its original diagnostic.
    /// - Throws: Typed admission errors, cancellation or original encoder/filesystem cause.
    /// - Note: Does not mark history saved. Concurrent external filesystem mutation and
    ///   power-loss directory durability are outside this prototype's guarantee. Admission is not a lease;
    ///   bind the publication coordinator to the owning editor session for current-revision output.
    public func export(
        _ document: Dust3DDocument, format: DocumentExportFormat, to destination: URL, sourceURL: URL?,
        validateSnapshot: @Sendable () async throws -> Void = {},
        publish: @Sendable (_ commit: @Sendable () throws -> Void) async throws -> Void = { commit in try commit() }
    ) async throws -> DocumentExportArtifact {
        try Task.checkCancellation()
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        let sourceScoped = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer { if sourceScoped { sourceURL?.stopAccessingSecurityScopedResource() } }
        try await validateSnapshot()
        try Task.checkCancellation()
        try Self.validate(destination, format: format, source: sourceURL)
        let output = try await encoder.encode(archive: document.encoded(), format: format)
        try Task.checkCancellation()
        guard !output.bytes.isEmpty, output.bytes.count <= Self.maximumBytes else {
            throw DocumentExportError.invalidOutput
        }
        try await validateSnapshot()
        try Task.checkCancellation()
        try await publish {
            try Task.checkCancellation()
            try Self.validate(destination, format: format, source: sourceURL)
            try output.bytes.write(to: destination, options: .atomic)
        }
        return output
    }

    private static func validate(_ destination: URL, format: DocumentExportFormat, source: URL?) throws {
        guard destination.isFileURL, destination.pathExtension.lowercased() == format.rawValue,
            source == nil || source?.isFileURL == true
        else { throw DocumentExportError.invalidDestination }
        if let source,
            destination.standardizedFileURL.resolvingSymlinksInPath()
                == source.standardizedFileURL.resolvingSymlinksInPath()
        {
            throw DocumentExportError.sourceAlias
        }
        let manager = FileManager.default
        let parent = try manager.attributesOfItem(atPath: destination.deletingLastPathComponent().path)
        guard parent[.type] as? FileAttributeType == .typeDirectory else {
            throw DocumentExportError.invalidDestination
        }
        let target: [FileAttributeKey: Any]
        do {
            target = try manager.attributesOfItem(atPath: destination.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        }
        guard target[.type] as? FileAttributeType == .typeRegular else { throw DocumentExportError.invalidDestination }
        if let source {
            let origin = try manager.attributesOfItem(atPath: source.resolvingSymlinksInPath().path)
            if let targetDevice = target[.systemNumber] as? NSNumber,
                let sourceDevice = origin[.systemNumber] as? NSNumber,
                let targetInode = target[.systemFileNumber] as? NSNumber,
                let sourceInode = origin[.systemFileNumber] as? NSNumber,
                targetDevice == sourceDevice, targetInode == sourceInode
            {
                throw DocumentExportError.sourceAlias
            }
        }
    }
}
