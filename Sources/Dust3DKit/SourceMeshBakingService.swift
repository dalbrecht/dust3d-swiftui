import Dust3DEngine
import Foundation

/// Serial background source-aware baking with owned Sendable output and cooperative native cancellation.
public actor SourceMeshBakingService {
    private let operation: any SourceMeshBakingOperation

    /// Create a service retaining no native mesh or caller pixel pointer.
    public init() { operation = NativeSourceMeshBakingOperation() }
    init(operation: any SourceMeshBakingOperation) { self.operation = operation }

    /// Generate and copy a source-aware bake off the main actor.
    /// - Parameters:
    ///   - data: Complete archive snapshot.
    ///   - modelImages: Matching imported model pixels, without material factors applied.
    ///   - images: Matching procedural image pixels.
    ///   - options: Dimensions and retained-output/input quotas.
    /// - Returns: Independent geometry, material policy, UVs, pixels and LOD restriction.
    /// - Throws: Original operation failure or CancellationError. Native work observes phase boundaries.
    /// - Example: `let mesh = try await SourceMeshBakingService().load(data: archive)`.
    public func load(
        data: Data, modelImages: [SourceMeshBakeImage] = [], images: [MeshBakeImage] = [],
        options: SourceMeshBakeOptions = SourceMeshBakeOptions()
    ) async throws -> SourceBakedMesh {
        try Task.checkCancellation()
        var error = Dust3DError()
        guard let pointer = dust3d_cancellation_token_create(&error) else { throw MeshLoader.loadingError(error) }
        let token = NativeBakeCancellation(pointer)
        defer { token.close() }
        return try await withTaskCancellationHandler {
            let result = try operation.load(
                data: data, modelImages: modelImages, images: images, options: options, cancellation: pointer)
            try Task.checkCancellation()
            return result
        } onCancel: {
            token.cancel()
        }
    }
}

/// Pointer is borrowed only during the actor's synchronous operation; never retain or destroy it.
protocol SourceMeshBakingOperation: Sendable {
    func load(
        data: Data, modelImages: [SourceMeshBakeImage], images: [MeshBakeImage], options: SourceMeshBakeOptions,
        cancellation: OpaquePointer
    ) throws -> SourceBakedMesh
}

struct NativeSourceMeshBakingOperation: SourceMeshBakingOperation {
    func load(
        data: Data, modelImages: [SourceMeshBakeImage], images: [MeshBakeImage], options: SourceMeshBakeOptions,
        cancellation: OpaquePointer
    ) throws -> SourceBakedMesh {
        try MeshLoader.loadSourceBaked(
            data: data, modelImages: modelImages, images: images, options: options, cancellation: cancellation)
    }
}
