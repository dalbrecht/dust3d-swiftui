import Dust3DEditorModel
import Dust3DKit
import Foundation
import Observation

/// One destination chooser belongs to one document window.
@MainActor
protocol EditorOBJExportDestinationChoosing: AnyObject {
    func chooseDestination(suggestedName: String) async throws -> URL?
    func cancel()
}

/// Retains task ownership through cancellation until the encoder has actually drained.
@MainActor @Observable
final class EditorOBJExportWorkflow {
    typealias Completion = Result<EditorExportReceipt?, any Error>
    private let store: EditorStore
    private let destinations: any EditorOBJExportDestinationChoosing
    private var task: Task<Completion, Never>?
    private var stopped = false
    private(set) var phase = EditorOBJExportPhase.idle

    init(store: EditorStore, destinations: any EditorOBJExportDestinationChoosing) {
        self.store = store
        self.destinations = destinations
    }

    var canBegin: Bool { !stopped && task == nil && store.canExport }
    var canCancel: Bool { task != nil && phase.canCancel }

    @discardableResult
    func begin(sourceURL: URL?) -> Task<Completion, Never>? {
        guard canBegin, let snapshot = store.snapshot else { return nil }
        let target = EditorExportTarget(snapshot: snapshot)
        let identity = snapshot.documentIdentity
        let revision = snapshot.documentRevision
        let stem = sourceURL?.deletingPathExtension().lastPathComponent
        let suggestedName = (stem.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled") + ".obj"
        if case .failed(let cause) = phase, store.errorMessage == EditorStore.message(cause) {
            store.errorMessage = nil
        }
        phase = .choosing
        let operation = Task<Completion, Never> { [self] in
            defer {
                task = nil
                if stopped { phase = .idle }
            }
            do {
                let destination = try await destinations.chooseDestination(suggestedName: suggestedName)
                try Task.checkCancellation()
                guard !stopped else { throw CancellationError() }
                guard let destination else {
                    phase = .idle
                    return .success(nil)
                }
                guard isCurrent(identity: identity, revision: revision) else { throw EditorError.staleExport }
                phase = .encoding
                let receipt = try await store.exportDocument(
                    format: .obj, to: destination, sourceURL: sourceURL, capturedTarget: target)
                // A late cancellation cannot turn an already committed receipt into an absent file.
                if !stopped, isCurrent(identity: receipt.documentIdentity, revision: receipt.documentRevision) {
                    phase = .completed(receipt)
                } else {
                    phase = .idle
                }
                return .success(receipt)
            } catch {
                if !stopped, isCurrent(identity: identity, revision: revision), !(error is CancellationError) {
                    store.errorMessage = EditorStore.message(error)
                    phase = .failed(error)
                } else {
                    phase = .idle
                }
                return .failure(error)
            }
        }
        task = operation
        return operation
    }

    private func isCurrent(identity: UUID, revision: Int) -> Bool {
        store.snapshot?.documentIdentity == identity && store.snapshot?.documentRevision == revision
    }

    func cancel() {
        guard let task, canCancel else { return }
        phase = .cancelling
        task.cancel()
        destinations.cancel()
    }

    func sourceDidChange() {
        if task != nil { cancel() } else { phase = .idle }
    }

    func stop() {
        stopped = true
        cancel()
        if task == nil { phase = .idle }
    }

    func dismissResult() {
        guard task == nil else { return }
        phase = .idle
    }
}
