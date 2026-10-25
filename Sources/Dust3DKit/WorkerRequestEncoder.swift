import Dust3DWorkerRuntime
import Foundation

/// Parent-issued correlation values. The parent must issue increasing request numbers across connections.
public struct WorkerRequestIdentity: Sendable, Equatable {
    public let document: UUID
    public let request: UInt64
    public let revision: UInt64

    /// Validate a nonzero document and request; revision is an independent parent-owned source epoch.
    /// - Throws: `WorkerRequestError.invalidIdentity`; no native work occurs.
    /// - Example: `try WorkerRequestIdentity(document: scope, request: 1, revision: 0)`.
    public init(document: UUID, request: UInt64, revision: UInt64) throws {
        var bytes = document.uuid
        guard request > 0, withUnsafeBytes(of: &bytes, { $0.contains { $0 != 0 } }) else {
            throw WorkerRequestError.invalidIdentity
        }
        self.document = document
        self.request = request
        self.revision = revision
    }
}

/// Logical wire quotas, not process-memory or CPU limits.
public struct WorkerRequestLimits: Sendable {
    public let maximumInputBytes: Int
    public let maximumOutputBytes: Int
    public let maximumFailureBytes: Int
    public static let standard = Self(input: 128 * 1024 * 1024, output: 256 * 1024 * 1024, failure: 4096)

    /// Create positive supported quotas; input/output are at most 256 MiB, diagnostics at most 64 KiB.
    /// - Throws: `WorkerRequestError.invalidLimits` before any retained input copy.
    /// - Example: `try WorkerRequestLimits(maximumInputBytes: 1024 * 1024)`.
    public init(
        maximumInputBytes: Int = 128 * 1024 * 1024,
        maximumOutputBytes: Int = 256 * 1024 * 1024,
        maximumFailureBytes: Int = 4096
    ) throws {
        guard (1...256 * 1024 * 1024).contains(maximumInputBytes),
            (1...256 * 1024 * 1024).contains(maximumOutputBytes),
            (1...64 * 1024).contains(maximumFailureBytes)
        else { throw WorkerRequestError.invalidLimits }
        self.init(input: maximumInputBytes, output: maximumOutputBytes, failure: maximumFailureBytes)
    }

    private init(input: Int, output: Int, failure: Int) {
        maximumInputBytes = input
        maximumOutputBytes = output
        maximumFailureBytes = failure
    }
}

/// Image identity and dimensions only; pixel bytes never enter the request options.
public struct WorkerRequestImage: Sendable {
    public let id: String
    public let width: UInt32
    public let height: UInt32

    /// Retain source spelling; the core codec validates UUID identity, dimensions and duplicate aliases.
    /// - Parameters: `id` is source UUID text; width/height describe pixels without retaining them.
    /// - Example: `WorkerRequestImage(id: imageID, width: 64, height: 64)`.
    public init(id: String, width: UInt32, height: UInt32) {
        self.id = id
        self.width = width
        self.height = height
    }
}

/// UV codec options. Zero texture size/metadata budget retains the core defaults.
public struct WorkerUvRequestOptions: Sendable {
    public let textureSize: UInt32
    public let metadataBudget: UInt64
    public let images: [WorkerRequestImage]

    /// Retain metadata for validation when encoding; no images or archives are decoded.
    /// - Parameters: Zero textureSize/metadataBudget use defaults; images contain identities/dimensions only.
    /// - Example: `WorkerUvRequestOptions(textureSize: 512)`.
    public init(textureSize: UInt32 = 0, metadataBudget: UInt64 = 0, images: [WorkerRequestImage] = []) {
        self.textureSize = textureSize
        self.metadataBudget = metadataBudget
        self.images = images
    }
}

/// Only the maintained base and UV mesh wire operations are available.
public enum WorkerRequestOperation: Sendable {
    case mesh
    case uv(options: WorkerUvRequestOptions)
}

/// Copied original bridge receipt. Diagnostic bytes remain available even when not valid UTF-8.
public struct WorkerRequestDiagnostic: Sendable, Equatable {
    public let status: UInt32
    public let source: UInt32
    public let code: Int32
    public let isTruncated: Bool
    public let cause: Data
}

/// Boundary rejection or original core codec failure; no generation/I/O failure is implied.
public enum WorkerRequestError: LocalizedError, Sendable, Equatable {
    case invalidIdentity, invalidLimits, emptyArchive, inputLimitExceeded, invalidOptions, invalidEncodedOutput
    case unsupportedABI(UInt32)
    case encoding(WorkerRequestDiagnostic)

    public var errorDescription: String? {
        switch self {
        case .invalidIdentity: "Worker requests require nonzero document and request identities."
        case .invalidLimits: "Worker wire limits are outside supported positive bounds."
        case .emptyArchive: "A worker request requires archive bytes."
        case .inputLimitExceeded: "The worker request exceeds its input quota."
        case .invalidOptions: "Worker image metadata exceeds supported count or identity text bounds."
        case .invalidEncodedOutput: "The worker codec returned inconsistent owned output."
        case .unsupportedABI(let version): "Unsupported worker runtime ABI: \(version)."
        case .encoding(let receipt): String(decoding: receipt.cause, as: UTF8.self)
        }
    }
}

/// Independent Swift copies. The expected header is for collection, not proof of authenticated completion.
public struct WorkerRequestPacket: Sendable {
    public let identity: WorkerRequestIdentity
    public let frame: Data
    public let expectedHeader: Data
}

/// Encodes through the core authority; no parsing, generation, transport, signing or publication occurs.
public enum WorkerRequestEncoder {
    /// Copy a bounded base/UV request before destroying its synchronous C owner.
    /// Call off the UI actor: caller input, native frame and Swift copies can coexist.
    /// - Parameters:
    ///   - archive: Immutable opaque `.ds3` bytes, not parsed by this codec.
    ///   - identity: Parent-issued correlation values, never taken from a reply.
    ///   - operation: Base mesh or UV metadata options; default is base mesh.
    ///   - limits: Positive supported logical wire quotas, independent of process RSS.
    /// - Returns: Sendable frame/header copies with no borrowed buffers or opaque handles.
    /// - Throws: `WorkerRequestError`, preserving original codec receipts when available.
    /// - Example: `try WorkerRequestEncoder.encode(archive: bytes, identity: identity)`.
    public static func encode(
        archive: Data, identity: WorkerRequestIdentity, operation: WorkerRequestOperation = .mesh,
        limits: WorkerRequestLimits = .standard
    ) throws -> WorkerRequestPacket {
        let abi = dust3d_worker_runtime_abi_version()
        guard abi == UInt32(DUST3D_WORKER_RUNTIME_ABI_VERSION) else { throw WorkerRequestError.unsupportedABI(abi) }
        guard !archive.isEmpty else { throw WorkerRequestError.emptyArchive }
        guard archive.count <= limits.maximumInputBytes else { throw WorkerRequestError.inputLimitExceeded }
        var nativeIdentity = Dust3DWorkerRequestIdentity()
        var document = identity.document.uuid
        withUnsafeMutableBytes(of: &nativeIdentity.document) { destination in
            withUnsafeBytes(of: &document) { destination.copyBytes(from: $0) }
        }
        nativeIdentity.request = identity.request
        nativeIdentity.revision = identity.revision
        let nativeLimits = Dust3DWorkerWireLimits(
            maximum_input_bytes: UInt64(limits.maximumInputBytes),
            maximum_output_bytes: UInt64(limits.maximumOutputBytes),
            maximum_failure_bytes: UInt64(limits.maximumFailureBytes))
        var result = Dust3DWorkerRequestResult()
        func create(_ operation: Dust3DWorkerOperation, _ options: UnsafePointer<Dust3DWorkerRequestUvOptions>?)
            -> OpaquePointer?
        {
            archive.withUnsafeBytes {
                dust3d_worker_request_create(
                    operation, nativeIdentity, $0.bindMemory(to: UInt8.self).baseAddress, $0.count,
                    options, nativeLimits, &result)
            }
        }
        let owner: OpaquePointer?
        switch operation {
        case .mesh: owner = create(DUST3D_WORKER_OPERATION_MESH, nil)
        case .uv(let options):
            guard options.images.count <= 10_000,
                options.images.allSatisfy({ [36, 38].contains($0.id.utf8.count) })
            else { throw WorkerRequestError.invalidOptions }
            // Retain at most 380 KiB of text. The core checks complete wire size before copying the archive.
            var text = Data()
            for image in options.images { text.append(contentsOf: image.id.utf8) }
            owner = text.withUnsafeBytes { storage in
                var offset = 0
                let images = options.images.map { image in
                    let count = image.id.utf8.count
                    defer { offset += count }
                    return Dust3DWorkerRequestImage(
                        identity: storage.baseAddress?.advanced(by: offset).assumingMemoryBound(to: CChar.self),
                        identity_size: count, width: image.width, height: image.height)
                }
                return images.withUnsafeBufferPointer { span in
                    var nativeOptions = Dust3DWorkerRequestUvOptions(
                        texture_size: options.textureSize, metadata_budget: options.metadataBudget,
                        images: span.baseAddress, image_count: span.count)
                    return withUnsafePointer(to: &nativeOptions) { create(DUST3D_WORKER_OPERATION_UV_MESH, $0) }
                }
            }
        }
        guard let owner else { throw WorkerRequestError.encoding(diagnostic(result)) }
        defer { dust3d_worker_request_destroy(owner) }
        guard result.status == DUST3D_WORKER_REQUEST_OK else { throw WorkerRequestError.encoding(diagnostic(result)) }
        var frameCount = 0
        var headerCount = 0
        guard let frame = dust3d_worker_request_bytes(owner, &frameCount),
            let header = dust3d_worker_request_header(owner, &headerCount),
            headerCount == 64, frameCount > headerCount, frameCount <= limits.maximumInputBytes + headerCount
        else { throw WorkerRequestError.invalidEncodedOutput }
        return WorkerRequestPacket(
            identity: identity, frame: Data(bytes: frame, count: frameCount),
            expectedHeader: Data(bytes: header, count: headerCount))
    }

    private static func diagnostic(_ receipt: Dust3DWorkerRequestResult) -> WorkerRequestDiagnostic {
        var receipt = receipt
        let cause = withUnsafeBytes(of: &receipt.message) { Data($0.prefix { $0 != 0 }) }
        return WorkerRequestDiagnostic(
            status: receipt.status.rawValue, source: receipt.detail_source.rawValue, code: receipt.detail_code,
            isTruncated: receipt.message_truncated != 0, cause: cause)
    }
}
