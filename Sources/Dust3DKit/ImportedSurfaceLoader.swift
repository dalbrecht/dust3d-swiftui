import Dust3DEngine
import Foundation

/// Copy the C surface owner off the main actor, releasing it on every exit path.
public enum ImportedSurfaceLoader {
    /// Generate and copy aligned geometry/source metadata from an exact archive snapshot.
    /// - Parameters:
    ///   - data: Complete archive bytes, at most 256 MiB.
    ///   - options: Independent native/Swift ownership budgets.
    /// - Returns: Immutable Sendable copies; source UVs are not packed atlas coordinates.
    /// - Throws: Original MeshLoadingError, ImportedSurfaceError or CancellationError.
    /// - Example: let surface = try ImportedSurfaceLoader.load(data: archive).
    public static func load(data: Data, options: ImportedSurfaceOptions = .init()) throws -> ImportedSurfaceMesh {
        try Task.checkCancellation()
        try validate(dataCount: data.count, options: options)
        var native = Dust3DImportedSurfaceOptions()
        native.struct_size = MemoryLayout<Dust3DImportedSurfaceOptions>.size
        native.maximum_payload_bytes = options.maximumNativePayloadBytes
        var error = Dust3DError()
        let owner = data.withUnsafeBytes {
            dust3d_imported_surface_mesh_load($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &native, &error)
        }
        guard let owner else { throw MeshLoader.loadingError(error) }
        defer { dust3d_imported_surface_mesh_destroy(owner) }
        return try ImportedSurfaceCopy.copy(owner, options: options)
    }

    static func validate(dataCount: Int, options: ImportedSurfaceOptions) throws {
        let ceiling = Int(DUST3D_MAX_IMPORTED_SURFACE_PAYLOAD_BYTES)
        guard (0...ceiling).contains(options.maximumNativePayloadBytes),
            (1...ceiling).contains(options.maximumCopiedPayloadBytes), dataCount >= 0
        else { throw ImportedSurfaceError.invalidLimits }
        guard dataCount <= MeshLoader.maximumFileSize else { throw ImportedSurfaceError.archiveLimitExceeded }
    }
}

/// Background source generation without retained native pointers or UI state.
public actor ImportedSurfaceService {
    private let operation: any ImportedSurfaceOperation
    public init() { operation = NativeImportedSurfaceOperation() }
    init(operation: any ImportedSurfaceOperation) { self.operation = operation }

    /// Copy source facts off the main actor with cancellation around synchronous native work.
    /// - Parameters: data is the exact archive snapshot; options bound retained output.
    /// - Returns: Independent geometry/source values.
    /// - Throws: Original operation error or cancellation; native work cannot be preempted.
    /// - Example: let surface = try await ImportedSurfaceService().load(data: archive).
    public func load(data: Data, options: ImportedSurfaceOptions = .init()) async throws -> ImportedSurfaceMesh {
        try Task.checkCancellation()
        let value = try operation.load(data: data, options: options)
        try Task.checkCancellation()
        return value
    }
}

protocol ImportedSurfaceOperation: Sendable {
    func load(data: Data, options: ImportedSurfaceOptions) throws -> ImportedSurfaceMesh
}
struct NativeImportedSurfaceOperation: ImportedSurfaceOperation {
    func load(data: Data, options: ImportedSurfaceOptions) throws -> ImportedSurfaceMesh {
        try ImportedSurfaceLoader.load(data: data, options: options)
    }
}

extension ImportedSurfaceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidLimits: return "The imported-surface limits are invalid."
        case .archiveLimitExceeded: return "The imported-surface archive exceeds 256 MiB."
        case .copyLimitExceeded: return "Copied surface data exceeds the configured output limit."
        case .invalidNativeCounts: return "The engine returned inconsistent surface buffer counts."
        case .invalidIdentity: return "The engine returned an invalid surface identity."
        case .invalidComponent: return "The engine returned an invalid surface component classification."
        case .invalidTriangle: return "The engine returned invalid source UV, RGBA or catalog references."
        }
    }
}
