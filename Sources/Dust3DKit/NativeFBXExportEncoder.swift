import Dust3DEngine
import Foundation

/// Static geometry export admission failures; original native errors remain `MeshLoadingError`.
public enum NativeFBXExportError: LocalizedError, Equatable {
    case invalidGeometryBudget(Int)
    case invalidOutputBudget(Int)
    case invalidArchiveByteCount(Int)
    case unsupportedFormat(DocumentExportFormat)
    case invalidNativeOutput

    public var errorDescription: String? {
        switch self {
        case .invalidGeometryBudget: "The FBX geometry limit must be positive and at most 256 MiB."
        case .invalidOutputBudget: "The FBX output limit must be positive and at most 256 MiB."
        case .invalidArchiveByteCount: "Choose a nonempty Dust3D archive no larger than 256 MiB."
        case .unsupportedFormat: "This encoder supports original procedural geometry in FBX format only."
        case .invalidNativeOutput: "The engine returned an invalid or out-of-bounds FBX output."
        }
    }
}

/// Serial off-main static GEOMETRY binding. No imported decoding, baking, rig or animation evaluation.
public actor NativeFBXExportEncoder: DocumentExportEncoding {
    private let maximumGeometryPayloadBytes: Int
    private let maximumOutputPayloadBytes: Int
    private let operation: any FBXExportOperation

    /// Construct without native work, with independent 64 MiB geometry/output logical payload quotas.
    /// These are not generation-workspace, allocator, time or RSS bounds.
    /// - Example: `DocumentExportFileService(encoder: NativeFBXExportEncoder())`.
    public init() {
        maximumGeometryPayloadBytes = 64 * 1024 * 1024
        maximumOutputPayloadBytes = 64 * 1024 * 1024
        operation = NativeFBXExportOperation()
    }

    /// Configure independent logical payload limits before native work.
    /// - Parameters: geometry and output limits are positive byte counts, each at most 256 MiB.
    /// - Throws: `NativeFBXExportError.invalidGeometryBudget` or `.invalidOutputBudget`.
    /// - Example: `try NativeFBXExportEncoder(maximumGeometryPayloadBytes: 64 << 20, maximumOutputPayloadBytes: 128 << 20)`.
    public init(maximumGeometryPayloadBytes: Int, maximumOutputPayloadBytes: Int) throws {
        try Self.validateBudgets(geometry: maximumGeometryPayloadBytes, output: maximumOutputPayloadBytes)
        self.maximumGeometryPayloadBytes = maximumGeometryPayloadBytes
        self.maximumOutputPayloadBytes = maximumOutputPayloadBytes
        operation = NativeFBXExportOperation()
    }

    init(maximumGeometryPayloadBytes: Int, maximumOutputPayloadBytes: Int, operation: any FBXExportOperation) throws {
        try Self.validateBudgets(geometry: maximumGeometryPayloadBytes, output: maximumOutputPayloadBytes)
        self.maximumGeometryPayloadBytes = maximumGeometryPayloadBytes
        self.maximumOutputPayloadBytes = maximumOutputPayloadBytes
        self.operation = operation
    }

    private static func validateBudgets(geometry: Int, output: Int) throws {
        guard (1...(256 * 1024 * 1024)).contains(geometry) else {
            throw NativeFBXExportError.invalidGeometryBudget(geometry)
        }
        guard (1...(256 * 1024 * 1024)).contains(output) else {
            throw NativeFBXExportError.invalidOutputBudget(output)
        }
    }

    static func validateArchiveByteCount(_ count: Int) throws {
        guard (1...MeshLoader.maximumFileSize).contains(count) else {
            throw NativeFBXExportError.invalidArchiveByteCount(count)
        }
    }

    static func validateCopiedOutput(bytes: Int, warningBytes: Int, maximum: Int) throws {
        guard bytes > 0, bytes <= maximum, (0...4096).contains(warningBytes), warningBytes <= maximum - bytes else {
            throw NativeFBXExportError.invalidNativeOutput
        }
    }

    /// Encode the captured archive and copy bytes/warning before releasing the C owner.
    /// - Parameters: archive is the exact complete source; format must be `.fbx`.
    /// - Returns: Owned static FBX bytes and original warning. Materials/textures/rig/animation are excluded.
    /// - Throws: Typed admission/native errors or Swift cancellation before/after synchronous work.
    /// No native cancellation is sent; imported archives reject before GLB decoding in the pinned bridge.
    /// - Example: `try await encoder.encode(archive: document.encoded(), format: .fbx)`.
    public func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        try Task.checkCancellation()
        guard format == .fbx else { throw NativeFBXExportError.unsupportedFormat(format) }
        try Self.validateArchiveByteCount(archive.count)
        let output = try operation.encode(
            archive: archive, maximumGeometryPayloadBytes: maximumGeometryPayloadBytes,
            maximumOutputPayloadBytes: maximumOutputPayloadBytes)
        try Task.checkCancellation()
        try Self.validateCopiedOutput(
            bytes: output.bytes.count, warningBytes: output.warning.utf8.count, maximum: maximumOutputPayloadBytes)
        return output
    }
}

protocol FBXExportOperation: Sendable {
    func encode(archive: Data, maximumGeometryPayloadBytes: Int, maximumOutputPayloadBytes: Int) throws
        -> DocumentExportArtifact
}

/// Borrowed views and destruction are confined to this synchronous call stack, without suspension.
struct NativeFBXExportOperation: FBXExportOperation {
    func encode(archive: Data, maximumGeometryPayloadBytes: Int, maximumOutputPayloadBytes: Int) throws
        -> DocumentExportArtifact
    {
        var options = Dust3DFbxExportOptions()
        options.struct_size = MemoryLayout<Dust3DFbxExportOptions>.size
        options.mode = UInt32(DUST3D_FBX_EXPORT_GEOMETRY)
        options.maximum_geometry_payload_bytes = maximumGeometryPayloadBytes
        options.maximum_output_payload_bytes = maximumOutputPayloadBytes
        var error = Dust3DError()
        let owner = archive.withUnsafeBytes { bytes in
            dust3d_fbx_export_load(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &options, &error)
        }
        guard let owner else { throw MeshLoader.loadingError(error) }
        defer { dust3d_fbx_export_destroy(owner) }
        let count = dust3d_fbx_export_byte_count(owner)
        let payload = dust3d_fbx_export_payload_bytes(owner)
        guard count > 0, count <= payload, payload <= maximumOutputPayloadBytes,
            let bytes = dust3d_fbx_export_bytes(owner), let warning = dust3d_fbx_export_warning(owner)
        else { throw NativeFBXExportError.invalidNativeOutput }
        let warningBytes = strnlen(warning, 4097)
        try NativeFBXExportEncoder.validateCopiedOutput(
            bytes: count, warningBytes: warningBytes, maximum: maximumOutputPayloadBytes)
        guard let message = String(validatingCString: warning) else { throw NativeFBXExportError.invalidNativeOutput }
        return DocumentExportArtifact(bytes: Data(bytes: bytes, count: count), warning: message)
    }
}
