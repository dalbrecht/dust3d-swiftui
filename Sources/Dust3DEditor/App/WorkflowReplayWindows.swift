import Dust3DDocument
import Foundation
import Observation

struct WorkflowReplayRequest {
    let id = UUID()
    let document: Dust3DDocument
}

/// Only a request ID crosses the scene boundary. The archive lives in this process while its replay is open.
@MainActor @Observable
final class WorkflowReplayWindows {
    private struct Entry {
        let request: WorkflowReplayRequest
        var owner: UUID?
        var expiration: Task<Void, Never>?
    }

    private let maximumCount: Int
    private let pendingLifetime: Duration
    private var entries: [UUID: Entry] = [:]
    var hasCapacity: Bool { entries.count < maximumCount }

    init(maximumCount: Int = 8, pendingLifetime: Duration = .seconds(30)) {
        self.maximumCount = maximumCount
        self.pendingLifetime = pendingLifetime
    }

    @discardableResult
    func open(_ document: Dust3DDocument, deliver: (UUID) -> Void) -> UUID? {
        guard hasCapacity else { return nil }
        let request = WorkflowReplayRequest(document: document)
        let id = request.id
        // An unpresented system window request must not hold a document or a slot indefinitely.
        let expiration = Task { [weak self, pendingLifetime] in
            do { try await Task.sleep(for: pendingLifetime) } catch { return }
            guard let self, let entry = self.entries[id], entry.owner == nil else { return }
            self.entries.removeValue(forKey: id)
        }
        entries[id] = Entry(request: request, expiration: expiration)
        deliver(id)
        return id
    }

    func attach(_ id: UUID?, owner: UUID) {
        guard let id, var entry = entries[id], entry.owner == nil else { return }
        entry.owner = owner
        entry.expiration?.cancel()
        entry.expiration = nil
        entries[id] = entry
    }

    func request(_ id: UUID?, owner: UUID) -> WorkflowReplayRequest? {
        guard let id, let entry = entries[id], entry.owner == owner else { return nil }
        return entry.request
    }

    func close(_ id: UUID?, owner: UUID) {
        guard let id, entries[id]?.owner == owner else { return }
        entries.removeValue(forKey: id)
    }
}

@MainActor
struct WorkflowReplayCommand {
    let documentForFocusedStore: (EditorStore?) -> Dust3DDocument?

    func invoke(in store: EditorStore?, windows: WorkflowReplayWindows, deliver: (UUID) -> Void) {
        guard windows.hasCapacity, let document = documentForFocusedStore(store) else { return }
        windows.open(document, deliver: deliver)
    }
}
