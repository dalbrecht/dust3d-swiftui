import Darwin
import Foundation
import os

/// Validation failures before any export file is created; filesystem failures retain their original NSError.
public enum ObjExportFileError: LocalizedError, Sendable, Equatable {
    case invalidDestination, emptyOutput

    public var errorDescription: String? {
        switch self {
        case .invalidDestination: "Choose a local OBJ file as the export destination."
        case .emptyOutput: "The OBJ export contains no geometry or bytes."
        }
    }
}

/// A receipt is returned only after the staged output has been committed atomically.
public struct ObjExportWriteReceipt: Sendable {
    public let destination: URL
    public let byteCount: Int
}

/// An explicit file boundary, separate from native generation and document state.
public protocol ObjExportFileWriting: Sendable {
    /// Stage and atomically commit one selected OBJ destination.
    /// - Parameters: output is owned geometry-only OBJ; destination is a local `.obj` file URL.
    /// - Returns: A receipt after commit; cancellation after commit does not undo a successful write.
    /// - Throws: Original filesystem error, ObjExportFileError or pre-commit CancellationError.
    func write(output: ObjExport, to destination: URL) async throws -> ObjExportWriteReceipt
}

/// Serial background export writes, retaining the destination until all staged bytes are ready.
public actor ObjExportFileService: ObjExportFileWriting {
    private let operation: any ObjExportFileOperation
    private let coordination: any ObjExportFileCoordinating
    private let logger = Logger(subsystem: "org.dust3d.export", category: "file-write")

    /// Create a file writer with no retained source document or native mesh.
    public init() {
        operation = NativeObjExportFileOperation()
        coordination = NativeObjExportFileCoordination()
    }
    init(
        operation: any ObjExportFileOperation,
        coordination: any ObjExportFileCoordinating = NativeObjExportFileCoordination()
    ) {
        self.operation = operation
        self.coordination = coordination
    }

    /// Write owned output off the main actor, preserving original failures and existing files.
    /// - Parameters: output is the admitted snapshot's bytes; destination must be an explicit local OBJ URL.
    /// - Returns: Committed URL and byte count.
    /// - Throws: Validation, cancellation or original filesystem cause before commit.
    /// - Example: `let receipt = try await ObjExportFileService().write(output: output, to: url)`.
    public func write(output: ObjExport, to destination: URL) async throws -> ObjExportWriteReceipt {
        try Task.checkCancellation()
        try ObjExportFileTransaction.validate(output: output, destination: destination)
        let operationID = UUID().uuidString
        return try await coordination.coordinate(destination: destination) { [operation, logger] admitted, check in
            try ObjExportFileTransaction.write(
                output: output, to: admitted, operation: operation,
                checkCancellation: check
            ) { error in
                logger.error(
                    "Export staging cleanup failed; operation=\(operationID, privacy: .public) cause=\(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }
}

protocol ObjExportFileOperation: Sendable {
    func makeStagingDirectory(for destination: URL) throws -> URL
    func write(_ data: Data, to stagedFile: URL) throws
    func commit(_ stagedFile: URL, to destination: URL) throws
    func removeStagingDirectory(_ directory: URL) throws
}

struct NativeObjExportFileOperation: ObjExportFileOperation {
    func makeStagingDirectory(for destination: URL) throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destination, create: true)
    }
    func write(_ data: Data, to stagedFile: URL) throws {
        try data.write(to: stagedFile, options: .withoutOverwriting)
    }
    func commit(_ stagedFile: URL, to destination: URL) throws {
        try stagedFile.withUnsafeFileSystemRepresentation { source in
            try destination.withUnsafeFileSystemRepresentation { target in
                guard let source, let target else { throw ObjExportFileError.invalidDestination }
                if Darwin.rename(source, target) != 0 {
                    let originalCode = errno
                    throw NSError(
                        domain: NSPOSIXErrorDomain, code: Int(originalCode),
                        userInfo: [NSURLErrorKey: destination])
                }
            }
        }
    }
    func removeStagingDirectory(_ directory: URL) throws {
        try FileManager.default.removeItem(at: directory)
    }
}

enum ObjExportFileTransaction {
    static func write(
        output: ObjExport, to destination: URL, operation: any ObjExportFileOperation,
        checkCancellation: ObjExportCancellationCheck = { try Task.checkCancellation() },
        cleanupFailed: (any Error) -> Void
    ) throws -> ObjExportWriteReceipt {
        try checkCancellation()
        try validate(output: output, destination: destination)
        let directory = try operation.makeStagingDirectory(for: destination)
        defer {
            do { try operation.removeStagingDirectory(directory) } catch { cleanupFailed(error) }
        }
        let stagedFile = directory.appendingPathComponent("output.obj")
        try operation.write(output.data, to: stagedFile)
        try checkCancellation()
        try operation.commit(stagedFile, to: destination)
        // Rename is the commit point. A later cancellation must not misreport the file as unwritten.
        return ObjExportWriteReceipt(destination: destination, byteCount: output.data.count)
    }

    static func validate(output: ObjExport, destination: URL) throws {
        guard destination.isFileURL, destination.query == nil, destination.fragment == nil,
            destination.host == nil || destination.host == "" || destination.host == "localhost",
            !destination.hasDirectoryPath, !destination.path.contains("\0"),
            destination.pathExtension.lowercased() == "obj"
        else { throw ObjExportFileError.invalidDestination }
        guard !output.data.isEmpty, output.vertexCount > 0, output.triangleCount > 0 else {
            throw ObjExportFileError.emptyOutput
        }
    }

}
