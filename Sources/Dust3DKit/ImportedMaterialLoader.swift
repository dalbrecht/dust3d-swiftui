import Dust3DEngine
import Foundation

/// C ownership boundary. Call off the main actor; returned data is independently owned.
public enum ImportedMaterialLoader {
    /// Inspect required embedded materials and copy views before releasing the C owner.
    /// - Parameters:
    ///   - data: Immutable complete archive bytes, at most 256 MiB.
    ///   - options: Independent native/Swift logical output budgets.
    /// - Returns: Sendable factors, original bindings and encoded image copies; no decoded pixels.
    /// - Throws: Original MeshLoadingError, typed ImportedMaterialError, or CancellationError.
    /// - Example: let materials = try ImportedMaterialLoader.load(data: archive).
    public static func load(data: Data, options: ImportedMaterialOptions = .init()) throws -> ImportedMaterials {
        try Task.checkCancellation()
        try validate(dataCount: data.count, options: options)
        var native = Dust3DImportedAssetOptions()
        native.struct_size = MemoryLayout<Dust3DImportedAssetOptions>.size
        native.maximum_payload_bytes = options.maximumNativePayloadBytes
        var error = Dust3DError()
        let owner = data.withUnsafeBytes {
            dust3d_imported_assets_load($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &native, &error)
        }
        guard let owner else { throw MeshLoader.loadingError(error) }
        defer { dust3d_imported_assets_destroy(owner) }
        return try ImportedMaterialCopy.copy(owner, options: options)
    }

    static func validate(dataCount: Int, options: ImportedMaterialOptions) throws {
        let ceiling = Int(DUST3D_MAX_IMPORTED_ASSET_PAYLOAD_BYTES)
        guard (0...ceiling).contains(options.maximumNativePayloadBytes),
            (1...ceiling).contains(options.maximumCopiedPayloadBytes), dataCount >= 0
        else { throw ImportedMaterialError.invalidLimits }
        guard dataCount <= MeshLoader.maximumFileSize else { throw ImportedMaterialError.archiveLimitExceeded }
    }
}

/// Background inspection with no retained native pointers or observable UI state.
public actor ImportedMaterialService {
    private let operation: any ImportedMaterialOperation

    public init() { operation = NativeImportedMaterialOperation() }
    init(operation: any ImportedMaterialOperation) { self.operation = operation }

    /// Inspect/copy off the main actor with cancellation around synchronous native work.
    /// - Parameters:
    ///   - data: Exact archive snapshot used for the accompanying geometry.
    ///   - options: Independent ownership budgets.
    /// - Returns: Independent immutable material/encoded-image values.
    /// - Throws: Original operation error or cancellation; native work cannot be preempted.
    /// - Example: let materials = try await ImportedMaterialService().load(data: archive).
    public func load(data: Data, options: ImportedMaterialOptions = .init()) async throws -> ImportedMaterials {
        try Task.checkCancellation()
        let value = try operation.load(data: data, options: options)
        try Task.checkCancellation()
        return value
    }
}

protocol ImportedMaterialOperation: Sendable {
    func load(data: Data, options: ImportedMaterialOptions) throws -> ImportedMaterials
}

struct NativeImportedMaterialOperation: ImportedMaterialOperation {
    func load(data: Data, options: ImportedMaterialOptions) throws -> ImportedMaterials {
        try ImportedMaterialLoader.load(data: data, options: options)
    }
}
