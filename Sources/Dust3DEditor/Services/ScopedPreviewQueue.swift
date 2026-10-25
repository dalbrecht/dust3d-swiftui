import Foundation

/// One latest value per scope, preserving FIFO scope order under replacement.
struct ScopedPreviewQueue<Work> {
    enum Submission {
        case queued(replaced: Work?)
        case full
    }

    private struct Entry {
        let scopeID: UUID
        let work: Work
    }
    private let maximumScopes: UInt
    private var entries: [Entry] = []

    /// Zero capacity disables waiting; replacement never consumes another slot.
    init(maximumScopes: UInt) { self.maximumScopes = maximumScopes }

    var count: Int { entries.count }

    mutating func submit(_ work: Work, scopeID: UUID) -> Submission {
        if let index = entries.firstIndex(where: { $0.scopeID == scopeID }) {
            let previous = entries[index].work
            entries[index] = Entry(scopeID: scopeID, work: work)
            return .queued(replaced: previous)
        }
        guard UInt(entries.count) < maximumScopes else { return .full }
        entries.append(Entry(scopeID: scopeID, work: work))
        return .queued(replaced: nil)
    }

    mutating func takeNext() -> Work? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst().work
    }

    mutating func remove(scopeID: UUID) -> Work? {
        guard let index = entries.firstIndex(where: { $0.scopeID == scopeID }) else { return nil }
        return entries.remove(at: index).work
    }

    mutating func remove(where matches: (Work) -> Bool) -> Work? {
        guard let index = entries.firstIndex(where: { matches($0.work) }) else { return nil }
        return entries.remove(at: index).work
    }
}

extension ScopedPreviewQueue.Submission: Equatable where Work: Equatable {}
