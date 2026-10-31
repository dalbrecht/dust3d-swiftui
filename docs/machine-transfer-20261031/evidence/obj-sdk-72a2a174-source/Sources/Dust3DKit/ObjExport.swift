import Foundation

/// Independent retained-data quotas; excludes generator workspace and allocator overhead.
public struct ObjExportOptions: Sendable {
    public let maximumSourcePayloadBytes: Int
    public let maximumIndexedPayloadBytes: Int
    public let maximumNativeOutputBytes: Int
    public let maximumCopiedPayloadBytes: Int

    /// Configure source geometry, indexing, native output and Swift copy limits.
    /// - Parameters:
    ///   - maximumSourcePayloadBytes: Zero selects the core's 64 MiB surface default; maximum 256 MiB.
    ///   - maximumIndexedPayloadBytes: Zero selects 256 MiB; maximum 256 MiB.
    ///   - maximumNativeOutputBytes: Zero selects 256 MiB; maximum 256 MiB, including owner/capacity.
    ///   - maximumCopiedPayloadBytes: Positive logical Swift root, bytes and warning limit, at most 256 MiB.
    public init(
        maximumSourcePayloadBytes: Int = 64 * 1024 * 1024,
        maximumIndexedPayloadBytes: Int = 64 * 1024 * 1024,
        maximumNativeOutputBytes: Int = 64 * 1024 * 1024,
        maximumCopiedPayloadBytes: Int = 64 * 1024 * 1024
    ) {
        self.maximumSourcePayloadBytes = maximumSourcePayloadBytes
        self.maximumIndexedPayloadBytes = maximumIndexedPayloadBytes
        self.maximumNativeOutputBytes = maximumNativeOutputBytes
        self.maximumCopiedPayloadBytes = maximumCopiedPayloadBytes
    }
}

/// Immutable owned geometry-only OBJ output; no C pointer or source mesh is retained.
public struct ObjExport: Sendable {
    public let data: Data
    public let vertexCount: Int
    public let triangleCount: Int
    public let warning: String
    public let nativePayloadBytes: Int
    public let copiedPayloadBytes: Int
}

/// Swift boundary failures; native statuses and causes remain MeshLoadingError values.
public enum ObjExportError: LocalizedError, Sendable, Equatable {
    case invalidLimits, archiveLimitExceeded, invalidNativeOutput, copyLimitExceeded

    public var errorDescription: String? {
        switch self {
        case .invalidLimits: "The OBJ export limits are invalid."
        case .archiveLimitExceeded: "The OBJ source archive exceeds 256 MiB."
        case .invalidNativeOutput: "The engine returned inconsistent OBJ output."
        case .copyLimitExceeded: "Copied OBJ output exceeds the configured limit."
        }
    }
}
