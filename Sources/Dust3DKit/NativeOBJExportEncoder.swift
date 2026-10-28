import Dust3DEngine
import Foundation

/// Capability/policy failures, separate from original typed C ABI failures.
public enum NativeOBJExportError: LocalizedError, Equatable {
    case invalidOutputBudget(Int)
    case unsupportedFormat(DocumentExportFormat)
    case invalidNativeOutput

    public var errorDescription: String? {
        switch self {
        case .invalidOutputBudget:
            return "The OBJ output limit must be positive and at most 256 MiB."
        case .unsupportedFormat:
            return "This encoder supports original procedural geometry in OBJ format only."
        case .invalidNativeOutput:
            return "The engine returned an empty or out-of-bounds OBJ output."
        }
    }
}

/// Original procedural positions/faces only. No preview reconstruction, UVs, materials, rig or animation.
/// The actor keeps synchronous C work off the UI actor; the canonical bridge serializes engine globals.
public actor NativeOBJExportEncoder: DocumentExportEncoding {
    private let maximumOutputPayloadBytes: Int
    private let operation: any OBJExportOperation

    /// Create a background encoder with the fixed 64 MiB native output profile.
    /// Construction never invokes native code or creates foreign owners.
    /// - Example: `let service = DocumentExportFileService(encoder: NativeOBJExportEncoder())`.
    public init() {
        maximumOutputPayloadBytes = 64 * 1024 * 1024
        operation = NativeOBJExportOperation()
    }

    /// Create a background encoder over the reviewed pinned original-geometry C ABI.
    /// - Parameter maximumOutputPayloadBytes: Positive native owner/warning/byte quota, at most 256 MiB.
    ///   Generation workspace and Swift copies are separate, not an RSS promise.
    /// - Throws: `NativeOBJExportError.invalidOutputBudget` before any native work.
    /// - Example: `let encoder = try NativeOBJExportEncoder(maximumOutputPayloadBytes: 128 * 1024 * 1024)`.
    public init(maximumOutputPayloadBytes: Int) throws {
        try Self.validateOutputBudget(maximumOutputPayloadBytes)
        self.maximumOutputPayloadBytes = maximumOutputPayloadBytes
        operation = NativeOBJExportOperation()
    }

    init(maximumOutputPayloadBytes: Int, operation: any OBJExportOperation) throws {
        try Self.validateOutputBudget(maximumOutputPayloadBytes)
        self.maximumOutputPayloadBytes = maximumOutputPayloadBytes
        self.operation = operation
    }

    private static func validateOutputBudget(_ count: Int) throws {
        guard (1...(256 * 1024 * 1024)).contains(count) else {
            throw NativeOBJExportError.invalidOutputBudget(count)
        }
    }

    /// Encode exactly the captured archive with independent owned Swift bytes/warning.
    /// - Parameters: archive is a nonempty complete archive up to 256 MiB; format must be `.obj`.
    /// - Returns: Original-geometry OBJ copied before releasing its native owner.
    /// - Throws: Original `MeshLoadingError`, capability/policy error or Swift cancellation.
    /// Cancellation is checked before/after work; it never sends native cancellation or claims preemption.
    /// Imported model assets are rejected by the pinned core before decoding; no GLB fallback is installed.
    public func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        try Task.checkCancellation()
        guard format == .obj else { throw NativeOBJExportError.unsupportedFormat(format) }
        try Self.validateArchiveByteCount(archive.count)
        let output = try operation.encode(archive: archive, maximumOutputPayloadBytes: maximumOutputPayloadBytes)
        try Task.checkCancellation()
        guard !output.bytes.isEmpty, output.bytes.count <= maximumOutputPayloadBytes else {
            throw NativeOBJExportError.invalidNativeOutput
        }
        return output
    }

    static func validateArchiveByteCount(_ count: Int) throws {
        guard count > 0 else {
            throw MeshLoadingError(status: DUST3D_STATUS_INVALID_DOCUMENT.rawValue, message: "The archive is empty.")
        }
        guard count <= MeshLoader.maximumFileSize else {
            throw MeshLoadingError(
                status: DUST3D_STATUS_LIMIT_EXCEEDED.rawValue, message: "The archive exceeds 256 MiB.")
        }
    }
}

protocol OBJExportOperation: Sendable {
    func encode(archive: Data, maximumOutputPayloadBytes: Int) throws -> DocumentExportArtifact
}

/// All foreign pointers stay on this synchronous actor-owned call stack and are copied before destroy.
struct NativeOBJExportOperation: OBJExportOperation {
    func encode(archive: Data, maximumOutputPayloadBytes: Int) throws -> DocumentExportArtifact {
        var options = Dust3DObjExportOptions()
        options.struct_size = MemoryLayout<Dust3DObjExportOptions>.size
        options.maximum_output_payload_bytes = maximumOutputPayloadBytes
        var error = Dust3DError()
        let handle = archive.withUnsafeBytes { bytes in
            dust3d_obj_export_load(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &options, &error)
        }
        guard let handle else { throw MeshLoader.loadingError(error) }
        defer { dust3d_obj_export_destroy(handle) }
        let count = dust3d_obj_export_byte_count(handle)
        guard count > 0, count <= maximumOutputPayloadBytes,
            let bytes = dust3d_obj_export_bytes(handle), let warning = dust3d_obj_export_warning(handle)
        else { throw NativeOBJExportError.invalidNativeOutput }
        return DocumentExportArtifact(bytes: Data(bytes: bytes, count: count), warning: String(cString: warning))
    }
}
