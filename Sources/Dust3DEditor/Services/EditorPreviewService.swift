import Dust3DKit
import Foundation

struct EditorPreviewOutput: Sendable {
    let mesh: IndexedMesh
    let sourceHints: MeshSourceHints?
}

struct EditorPreviewResult: Sendable {
    let output: EditorPreviewOutput?
    let statistics: MeshGenerationStatistics
    let sourceIssue: MeshLoadingError?
    var mesh: IndexedMesh? { output?.mesh }

    init(sourced: SourcedMeshGenerationResult) {
        output = sourced.mesh.map { EditorPreviewOutput(mesh: $0, sourceHints: sourced.sourceHints) }
        statistics = sourced.statistics
        sourceIssue = nil
    }

    init(ordinary: MeshGenerationResult, sourceIssue: MeshLoadingError) {
        output = ordinary.mesh.map { EditorPreviewOutput(mesh: $0, sourceHints: nil) }
        statistics = ordinary.statistics
        self.sourceIssue = sourceIssue
    }
}

struct EditorPreviewFallbackError: LocalizedError {
    let source: MeshLoadingError
    let geometryMessage: String
    var errorDescription: String? {
        source.message == geometryMessage ? geometryMessage : "\(geometryMessage)\nSource details: \(source.message)"
    }
}

protocol EditorPreviewServing: Sendable {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult
    func reset(scopeID: UUID) async throws
}

protocol EditorMeshGenerating: Sendable {
    func generateSourcedIndexed(data: Data, maximumPayloadBytes: Int, maximumSourcePayloadBytes: Int) async throws
        -> SourcedMeshGenerationResult
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
    private let maximumSourcePayloadBytes: Int
    private var current: Context?
    private var tail: Task<Void, Never>?
    private let makeSession: @Sendable (Int) throws -> any EditorMeshGenerating

    init(
        maximumCachePayloadBytes: Int = MeshGenerationSession.defaultMaximumCachePayloadBytes,
        maximumSourcePayloadBytes: Int = 0,
        makeSession: @escaping @Sendable (Int) throws -> any EditorMeshGenerating = {
            try MeshGenerationSession(maximumCachePayloadBytes: $0)
        }
    ) {
        self.maximumCachePayloadBytes = maximumCachePayloadBytes
        self.maximumSourcePayloadBytes = maximumSourcePayloadBytes
        self.makeSession = makeSession
    }

    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
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

    private func generateNow(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        let session: any EditorMeshGenerating
        if let current, current.scopeID == scopeID {
            session = current.session
        } else {
            session = try makeSession(maximumCachePayloadBytes)
            current = Context(scopeID: scopeID, session: session)
        }
        do {
            let result = try await session.generateSourcedIndexed(
                data: data, maximumPayloadBytes: 0, maximumSourcePayloadBytes: maximumSourcePayloadBytes)
            try Task.checkCancellation()
            return EditorPreviewResult(sourced: result)
        } catch let source as MeshLoadingError where source.status == 3 || source.status == 4 {
            // Optional source output must not prevent an otherwise valid mesh preview.
            try Task.checkCancellation()
            do {
                let result = try await session.generateIndexed(data: data, maximumPayloadBytes: 0)
                try Task.checkCancellation()
                return EditorPreviewResult(ordinary: result, sourceIssue: source)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw EditorPreviewFallbackError(source: source, geometryMessage: error.localizedDescription)
            }
        }
    }

    private func resetNow(scopeID: UUID) async throws {
        guard let previous = current, previous.scopeID == scopeID else { return }
        // Detach before awaiting and mutate no newer context after cleanup.
        current = nil
        try await previous.session.reset()
    }
}
