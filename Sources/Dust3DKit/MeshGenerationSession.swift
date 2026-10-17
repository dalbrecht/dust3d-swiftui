import Dust3DEngine
import Foundation
import os

/// Retention outcome for the most recent generation or reset.
public enum MeshCacheOutcome: Sendable, Equatable {
    case empty
    case disabled
    case retained
    case bypassed
    case resetAfterFailure
    case unknown(UInt32)

    init(native: Dust3DCacheOutcome) {
        switch native {
        case DUST3D_CACHE_EMPTY: self = .empty
        case DUST3D_CACHE_DISABLED: self = .disabled
        case DUST3D_CACHE_RETAINED: self = .retained
        case DUST3D_CACHE_BYPASSED: self = .bypassed
        case DUST3D_CACHE_RESET_AFTER_FAILURE: self = .resetAfterFailure
        default: self = .unknown(native.rawValue)
        }
    }
}

/// Immutable copied cache diagnostics. Payload accounting excludes allocator overhead,
/// temporary workspace, caller-owned mesh buffers and process memory.
public struct MeshGenerationStatistics: Sendable {
    /// Configured retained payload ceiling, excluding transient workspace.
    public let maximumCachePayloadBytes: Int
    /// Accounted retained object/value/buffer bytes after the last operation.
    public let retainedPayloadBytes: Int
    /// Actual component mesh cache hits during the last native generation.
    public let reusedComponentCount: Int
    /// Actual component rebuilds during the last native generation.
    public let rebuiltComponentCount: Int
    /// Actual part rebuilds during the last native generation.
    public let rebuiltPartCount: Int
    /// Retention result after generation, failure or reset.
    public let outcome: MeshCacheOutcome
    /// Original cache-only cause, independent of a primary generation error.
    public let cacheIssue: MeshLoadingError?

    init(native: Dust3DGenerationStats) {
        maximumCachePayloadBytes = native.maximum_cache_payload_bytes
        retainedPayloadBytes = native.retained_payload_bytes
        reusedComponentCount = native.reused_components
        rebuiltComponentCount = native.rebuilt_components
        rebuiltPartCount = native.rebuilt_parts
        outcome = MeshCacheOutcome(native: native.cache_outcome)
        if native.cache_status == DUST3D_STATUS_OK {
            cacheIssue = nil
        } else {
            var error = Dust3DError()
            error.status = native.cache_status
            error.message = native.cache_message
            cacheIssue = MeshLoader.loadingError(error)
        }
    }
}

/// A copied preview result. Nil geometry means explicit successful no-geometry.
public struct MeshGenerationResult: Sendable {
    /// Independent Swift buffers, or nil for explicit successful no-geometry.
    public let mesh: IndexedMesh?
    /// Copied cache diagnostics corresponding to this result.
    public let statistics: MeshGenerationStatistics
}

/// Independent geometry, source hints, and cache diagnostics from one sourced generation.
public struct SourcedMeshGenerationResult: Sendable {
    /// Nil only for explicit successful no-geometry.
    public let mesh: IndexedMesh?
    /// Per-index-position hints; nil together with empty geometry.
    public let sourceHints: MeshSourceHints?
    /// Current cache outcome, independent of source and indexed payload budgets.
    public let statistics: MeshGenerationStatistics
}

/// Owns one bounded native cache and copies every output buffer before releasing it.
/// Calls run on this background actor; native generation also shares the core's global lock.
/// Cancellation is cooperative before/after generation and does not interrupt C++ work.
/// Example: `let result = try await MeshGenerationSession().generateIndexed(data: archive)`.
public actor MeshGenerationSession {
    /// Core-defined default retained payload limit (64 MiB).
    public static let defaultMaximumCachePayloadBytes = Int(DUST3D_DEFAULT_CACHE_PAYLOAD_BYTES)
    /// Core-defined largest supported retained payload limit (256 MiB).
    public static let maximumCachePayloadBytes = Int(DUST3D_MAX_CACHE_PAYLOAD_BYTES)

    /// Core-defined default source export payload (64 MiB); zero selects this value.
    public static let defaultSourcePayloadBytes = Int(DUST3D_DEFAULT_SOURCE_PAYLOAD_BYTES)
    /// Largest supported native source export payload (256 MiB).
    public static let maximumSourcePayloadBytes = Int(DUST3D_MAX_SOURCE_PAYLOAD_BYTES)

    // The opaque pointer never leaves a synchronous lock region. This system lock
    // keeps deinit safe without an unchecked Sendable declaration or a newer OS baseline.
    private let handle: OSAllocatedUnfairLock<OpaquePointer>

    /// Create an empty cache owner. Zero disables retention; the supported maximum is 256 MiB.
    /// - Parameter maximumCachePayloadBytes: Retained object/value/buffer payload limit.
    /// - Throws: `MeshLoadingError` for negative, unsupported or unallocatable budgets.
    public init(maximumCachePayloadBytes: Int = defaultMaximumCachePayloadBytes) throws {
        guard maximumCachePayloadBytes >= 0 else {
            throw MeshLoadingError(status: 1, message: "The cache payload budget must be zero or positive.")
        }
        guard maximumCachePayloadBytes <= Self.maximumCachePayloadBytes else {
            throw MeshLoadingError(status: 4, message: "The session cache budget exceeds 256 MiB.")
        }
        var error = Dust3DError()
        guard let native = dust3d_generation_session_create(maximumCachePayloadBytes, &error) else {
            throw MeshLoader.loadingError(error)
        }
        handle = OSAllocatedUnfairLock(uncheckedState: native)
    }

    deinit { handle.withLock { dust3d_generation_session_destroy($0) } }

    /// Generate an indexed preview and copy its cache diagnostics.
    /// - Parameters:
    ///   - data: Complete borrowed `.ds3` archive bytes, not retained by the wrapper.
    ///   - maximumPayloadBytes: Native indexed output budget; zero selects 256 MiB.
    ///     This is separate from the cache budget, whose zero disables retention.
    /// - Returns: Independent Swift geometry, or nil only for explicit successful emptiness, plus stats.
    /// - Throws: Cancellation or `MeshLoadingError` preserving the primary native cause.
    ///   Cache-only failures are reported in statistics and do not fail valid generation.
    public func generateIndexed(data: Data, maximumPayloadBytes: Int = 0) throws -> MeshGenerationResult {
        try Task.checkCancellation()
        try MeshLoader.validateIndexedPayloadBudget(maximumPayloadBytes)
        let mesh: IndexedMesh? = try handle.withLock { native in
            var error = Dust3DError()
            let expanded = data.withUnsafeBytes { bytes in
                dust3d_generation_session_load(
                    native, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &error)
            }
            guard let expanded else {
                if error.status == DUST3D_STATUS_NO_GEOMETRY { return nil }
                throw MeshLoader.loadingError(error)
            }
            let indexed: OpaquePointer
            do {
                defer { dust3d_mesh_destroy(expanded) }
                try Task.checkCancellation()
                indexed = try MeshLoader.makeNativeIndexedMesh(from: expanded, maximumPayloadBytes: maximumPayloadBytes)
            }
            return try MeshLoader.copyAndDestroyIndexedMesh(indexed)
        }
        let statistics = try statistics()
        try Task.checkCancellation()
        return MeshGenerationResult(mesh: mesh, statistics: statistics)
    }

    /// Generate indexed geometry and copied source hints without losing component cache reuse.
    /// - Parameters:
    ///   - data: Complete borrowed `.ds3` archive bytes.
    ///   - maximumPayloadBytes: Native indexed vertex/index budget; zero selects 256 MiB.
    ///   - maximumSourcePayloadBytes: Native source logical payload; zero selects 64 MiB.
    ///     Excludes geometry, spare capacity, allocator overhead, workspace and Swift copies.
    /// - Returns: Independent geometry, hints and stats; both geometry/hints nil for successful emptiness.
    /// - Throws: Cancellation or `MeshLoadingError`, including invalid UTF-8/source metadata,
    ///   negative/unsupported budgets and original native primary failures. Cache-only issues stay in stats.
    /// - Example: `let result = try await session.generateSourcedIndexed(data: archive)`.
    public func generateSourcedIndexed(
        data: Data, maximumPayloadBytes: Int = 0, maximumSourcePayloadBytes: Int = 0
    ) throws -> SourcedMeshGenerationResult {
        try Task.checkCancellation()
        try MeshLoader.validateIndexedPayloadBudget(maximumPayloadBytes)
        guard maximumSourcePayloadBytes >= 0 else {
            throw MeshLoadingError(status: 1, message: "The source payload budget must be zero or positive.")
        }
        guard maximumSourcePayloadBytes <= Self.maximumSourcePayloadBytes else {
            throw MeshLoadingError(status: 4, message: "The source payload budget exceeds 256 MiB.")
        }
        let sourceLimit = maximumSourcePayloadBytes == 0 ? Self.defaultSourcePayloadBytes : maximumSourcePayloadBytes
        let copied: (mesh: IndexedMesh?, hints: MeshSourceHints?) = try handle.withLock { native in
            var error = Dust3DError()
            var options = Dust3DSourceOptions(
                struct_size: MemoryLayout<Dust3DSourceOptions>.size, maximum_payload_bytes: maximumSourcePayloadBytes)
            let owner = data.withUnsafeBytes { bytes in
                dust3d_generation_session_load_sourced(
                    native, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &options, &error)
            }
            guard let owner else {
                if error.status == DUST3D_STATUS_NO_GEOMETRY { return (nil, nil) }
                throw MeshLoader.loadingError(error)
            }
            let indexed: OpaquePointer
            let hints: MeshSourceHints
            do {
                defer { dust3d_sourced_mesh_destroy(owner) }
                try Task.checkCancellation()
                guard let geometry = dust3d_sourced_mesh_geometry(owner) else {
                    throw MeshLoadingError(status: 3, message: "The engine returned source hints without geometry.")
                }
                hints = try MeshSourceCopy.copy(owner, geometry: geometry, maximumPayloadBytes: sourceLimit)
                try Task.checkCancellation()
                indexed = try MeshLoader.makeNativeIndexedMesh(from: geometry, maximumPayloadBytes: maximumPayloadBytes)
            }
            // Drop expanded native geometry and source buffers before allocating Swift indexed copies.
            return (try MeshLoader.copyAndDestroyIndexedMesh(indexed), hints)
        }
        let statistics = try statistics()
        try Task.checkCancellation()
        return SourcedMeshGenerationResult(mesh: copied.mesh, sourceHints: copied.hints, statistics: statistics)
    }

    /// Copy the last native statistics, including after a failed generation.
    /// - Returns: Independent immutable diagnostics and actual per-call reuse/rebuild counts.
    /// - Throws: `MeshLoadingError` if the native statistics query fails.
    public func statistics() throws -> MeshGenerationStatistics {
        try handle.withLock { native in
            var stats = Dust3DGenerationStats()
            var error = Dust3DError()
            guard
                dust3d_generation_session_get_stats(native, &stats, MemoryLayout.size(ofValue: stats), &error)
                    == DUST3D_STATUS_OK
            else {
                throw MeshLoader.loadingError(error)
            }
            return MeshGenerationStatistics(native: stats)
        }
    }

    /// Release all retained state and clear metrics while preserving the configured budget.
    /// - Throws: `MeshLoadingError` if the native reset fails.
    /// - Example: `try await session.reset()`.
    public func reset() throws {
        try handle.withLock { native in
            var error = Dust3DError()
            guard dust3d_generation_session_reset(native, &error) == DUST3D_STATUS_OK else {
                throw MeshLoader.loadingError(error)
            }
        }
    }
}
