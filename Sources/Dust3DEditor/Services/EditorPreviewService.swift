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
        source.message == geometryMessage
            ? geometryMessage : "\(geometryMessage)\nSource details: \(source.message)"
    }
}

protocol EditorPreviewServing: Sendable {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult
    func reset(scopeID: UUID) async throws
}

protocol EditorMeshGenerating: Sendable {
    func generateSourcedIndexed(data: Data, maximumPayloadBytes: Int, maximumSourcePayloadBytes: Int)
        async throws
        -> SourcedMeshGenerationResult
    func generateIndexed(data: Data, maximumPayloadBytes: Int) async throws -> MeshGenerationResult
    func reset() async throws
}

extension MeshGenerationSession: EditorMeshGenerating {}

enum EditorPreviewSchedulingError: LocalizedError {
    case resetBacklog

    var errorDescription: String? {
        "Preview cache cleanup is already queued; the reset backlog is full."
    }
}

/// One active backend job, one latest waiting preview and at most two cleanup barriers.
/// Native work remains serial across actor suspension points; cancellation is cooperative.
actor EditorPreviewService: EditorPreviewServing {
    private struct Context {
        let scopeID: UUID
        let session: any EditorMeshGenerating
    }
    private let maximumCachePayloadBytes: Int
    private let maximumSourcePayloadBytes: Int
    private var current: Context?
    private struct PreviewWork: Sendable {
        let id: UUID
        let data: Data
        let scopeID: UUID
        let continuation: CheckedContinuation<EditorPreviewResult, any Error>
    }
    private struct ResetWork: Sendable {
        let id: UUID
        let scopeID: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }
    private enum Work: Sendable {
        case generate(PreviewWork)
        case reset(ResetWork)

        var id: UUID {
            switch self {
            case .generate(let work): work.id
            case .reset(let work): work.id
            }
        }
        var scopeID: UUID {
            switch self {
            case .generate(let work): work.scopeID
            case .reset(let work): work.scopeID
            }
        }
    }
    private struct Active {
        let id: UUID
        let scopeID: UUID
        let task: Task<Void, Never>
    }
    private var active: Active?
    private var waitingPreview: PreviewWork?
    private var waitingResets: [ResetWork] = []
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
        let id = UUID()
        return try await withTaskCancellationHandler {
            let result = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<EditorPreviewResult, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                submitPreview(PreviewWork(id: id, data: data, scopeID: scopeID, continuation: continuation))
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func reset(scopeID: UUID) async throws {
        // Cleanup outlives caller cancellation, but never retains an unbounded chain.
        try await withCheckedThrowingContinuation { continuation in
            submitReset(ResetWork(id: UUID(), scopeID: scopeID, continuation: continuation))
        }
    }

    private func submitPreview(_ work: PreviewWork) {
        waitingPreview?.continuation.resume(throwing: CancellationError())
        waitingPreview = nil
        if active == nil {
            start(.generate(work))
        } else {
            waitingPreview = work
        }
    }

    private func submitReset(_ work: ResetWork) {
        if waitingPreview?.scopeID == work.scopeID {
            waitingPreview?.continuation.resume(throwing: CancellationError())
            waitingPreview = nil
        }
        guard current?.scopeID == work.scopeID || active?.scopeID == work.scopeID else {
            work.continuation.resume()
            return
        }
        if active == nil {
            start(.reset(work))
        } else if waitingResets.count < 2 {
            waitingResets.append(work)
        } else {
            work.continuation.resume(throwing: EditorPreviewSchedulingError.resetBacklog)
        }
    }

    private func cancel(_ id: UUID) {
        if active?.id == id {
            active?.task.cancel()
        } else if waitingPreview?.id == id {
            waitingPreview?.continuation.resume(throwing: CancellationError())
            waitingPreview = nil
        }
    }

    private func start(_ work: Work) {
        let task = Task { await perform(work) }
        active = Active(id: work.id, scopeID: work.scopeID, task: task)
    }

    private func perform(_ work: Work) async {
        switch work {
        case .generate(let preview):
            do {
                try Task.checkCancellation()
                let result = try await generateNow(preview.data, scopeID: preview.scopeID)
                try Task.checkCancellation()
                preview.continuation.resume(returning: result)
            } catch {
                preview.continuation.resume(throwing: error)
            }
        case .reset(let reset):
            do {
                try await resetNow(scopeID: reset.scopeID)
                reset.continuation.resume()
            } catch {
                reset.continuation.resume(throwing: error)
            }
        }
        active = nil
        // Prioritize old-scope cleanup without displacing the newest preview archive.
        if !waitingResets.isEmpty {
            start(.reset(waitingResets.removeFirst()))
        } else if let next = waitingPreview {
            waitingPreview = nil
            start(.generate(next))
        }
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
                throw EditorPreviewFallbackError(
                    source: source, geometryMessage: error.localizedDescription)
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
