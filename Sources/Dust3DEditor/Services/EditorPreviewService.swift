import Dust3DKit
import Foundation

protocol EditorPreviewServing: Sendable {
    func generate(_ data: Data, scopeID: UUID) async throws -> MeshGenerationResult
    func reset(scopeID: UUID) async throws
}

protocol EditorMeshGenerating: Sendable {
    func generateIndexed(data: Data, maximumPayloadBytes: Int) async throws -> MeshGenerationResult
    func reset() async throws
}

extension MeshGenerationSession: EditorMeshGenerating {}

/// One current document scope with serial backend work across actor suspension points.
actor EditorPreviewService: EditorPreviewServing {
    private struct Context {
        let scopeID: UUID
        let session: any EditorMeshGenerating
    }
    private let maximumCachePayloadBytes: Int
    private var current: Context?
    private var tail: Task<Void, Never>?
    private let makeSession: @Sendable (Int) throws -> any EditorMeshGenerating

    init(
        maximumCachePayloadBytes: Int = MeshGenerationSession.defaultMaximumCachePayloadBytes,
        makeSession: @escaping @Sendable (Int) throws -> any EditorMeshGenerating = {
            try MeshGenerationSession(maximumCachePayloadBytes: $0)
        }
    ) {
        self.maximumCachePayloadBytes = maximumCachePayloadBytes
        self.makeSession = makeSession
    }

    func generate(_ data: Data, scopeID: UUID) async throws -> MeshGenerationResult {
        try Task.checkCancellation()
        let operation = enqueue { [self] in
            try Task.checkCancellation()
            return try await generateNow(data, scopeID: scopeID)
        }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    func reset(scopeID: UUID) async throws {
        // Cleanup completes even if its caller is cancelled; scope matching protects
        // newer owners and the original error is still returned to the caller.
        let operation = enqueue { [self] in try await resetNow(scopeID: scopeID) }
        try await operation.value
    }

    private func enqueue<Output: Sendable>(
        _ body: @escaping @Sendable () async throws -> Output
    ) -> Task<Output, any Error> {
        let previous = tail
        let operation = Task {
            await previous?.value
            return try await body()
        }
        // Wait for either outcome for ordering; the original caller consumes errors.
        tail = Task { _ = await operation.result }
        return operation
    }

    private func generateNow(_ data: Data, scopeID: UUID) async throws -> MeshGenerationResult {
        let session: any EditorMeshGenerating
        if let current, current.scopeID == scopeID {
            session = current.session
        } else {
            session = try makeSession(maximumCachePayloadBytes)
            current = Context(scopeID: scopeID, session: session)
        }
        let result = try await session.generateIndexed(data: data, maximumPayloadBytes: 0)
        try Task.checkCancellation()
        return result
    }

    private func resetNow(scopeID: UUID) async throws {
        guard let previous = current, previous.scopeID == scopeID else { return }
        // Detach before awaiting and mutate no newer context after cleanup.
        current = nil
        try await previous.session.reset()
    }
}
