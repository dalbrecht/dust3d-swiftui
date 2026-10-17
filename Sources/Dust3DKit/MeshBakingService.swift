import Dust3DEngine
import Foundation
import os

/// Background CPU baking with copied Sendable output and native cooperative cancellation.
/// One actor serializes its own requests; the core also serializes inherited globals.
public actor MeshBakingService {
    private let operation: any MeshBakingOperation

    /// Create an independent background service with no retained native mesh state.
    public init() { operation = NativeMeshBakingOperation() }

    init(operation: any MeshBakingOperation) { self.operation = operation }

    /// Bake off the main actor while preserving all native ownership boundaries.
    /// - Parameters:
    ///   - data: Complete archive bytes, copied by value across actor boundaries.
    ///   - images: Caller-decoded straight-alpha RGBA8 inputs.
    ///   - options: Explicit dimensions and independent logical output quotas.
    /// - Returns: Independent Swift geometry, UVs, tangent frames and pixels.
    /// - Throws: `CancellationError` at Swift cancellation checks or `MeshLoadingError`
    ///   preserving native status/cause (including status 6 for native cancellation).
    /// Cancellation does not preempt inherited generation; it observes phase boundaries.
    /// - Example: `let output = try await MeshBakingService().load(data: archive)`.
    public func load(
        data: Data, images: [MeshBakeImage] = [], options: MeshBakeOptions = MeshBakeOptions()
    ) async throws -> MeshWithBakedTextures {
        try Task.checkCancellation()
        var error = Dust3DError()
        guard let pointer = dust3d_cancellation_token_create(&error) else { throw MeshLoader.loadingError(error) }
        let token = NativeBakeCancellation(pointer)
        defer { token.close() }
        return try await withTaskCancellationHandler {
            try operation.load(data: data, images: images, options: options, cancellation: pointer)
        } onCancel: {
            token.cancel()
        }
    }
}

/// A checked Sendable owner backed by the system's lock container. Only the
/// operation's actor-local pointer is borrowed during loading. Cancel/close use
/// this shared lock; no pointer is returned through a Sendable closure or result.
final class NativeBakeCancellation: Sendable {
    private let state: OSAllocatedUnfairLock<OpaquePointer?>

    init(_ pointer: OpaquePointer) {
        // C explicitly permits atomic cancellation concurrent with loading. The
        // non-Sendable foreign handle is confined to lock-protected cancel/destroy;
        // the operation must finish before close. No custom unchecked conformance.
        state = OSAllocatedUnfairLock(uncheckedState: pointer)
    }

    func cancel() {
        state.withLock { pointer in
            if let pointer { dust3d_cancellation_token_cancel(pointer) }
        }
    }

    func close() {
        state.withLock { pointer in
            if let live = pointer {
                dust3d_cancellation_token_destroy(live)
                pointer = nil
            }
        }
    }

    deinit { close() }
}

/// Synchronous foreign boundary used only while the actor pins its token lifetime.
/// Implementations must not retain the pointer or destroy it.
protocol MeshBakingOperation: Sendable {
    func load(data: Data, images: [MeshBakeImage], options: MeshBakeOptions, cancellation: OpaquePointer) throws
        -> MeshWithBakedTextures
}

struct NativeMeshBakingOperation: MeshBakingOperation {
    func load(data: Data, images: [MeshBakeImage], options: MeshBakeOptions, cancellation: OpaquePointer) throws
        -> MeshWithBakedTextures
    {
        try MeshLoader.loadBaked(data: data, images: images, options: options, cancellation: cancellation)
    }
}
