import Foundation
import os

enum EditorSaveError: Error, Equatable, LocalizedError {
    case editInProgress
    case obsoleteSnapshot

    var failureReason: String? { errorDescription }
    var recoverySuggestion: String? {
        switch self {
        case .editInProgress: "Wait until the editor finishes applying the edit, then save again."
        case .obsoleteSnapshot: "Save again to write the current document."
        }
    }

    var errorDescription: String? {
        switch self {
        case .editInProgress: "An edit is still being applied."
        case .obsoleteSnapshot:
            "The document changed while this save was being prepared."
        }
    }
}

/// FileDocument copies share only this bounded synchronization token, never a mutable archive or history.
final class EditorSaveState: Sendable {
    private struct State: Sendable {
        var version: UUID
        var isEditing = false
    }
    private let state: OSAllocatedUnfairLock<State>

    init(version: UUID) { state = OSAllocatedUnfairLock(initialState: State(version: version)) }

    func setEditing(_ isEditing: Bool) { state.withLock { $0.isEditing = isEditing } }

    func publish() -> UUID {
        let version = UUID()
        state.withLock { $0.version = version }
        return version
    }

    func validate(_ version: UUID) throws {
        try state.withLock { current in
            guard !current.isEditing else { throw EditorSaveError.editInProgress }
            guard current.version == version else { throw EditorSaveError.obsoleteSnapshot }
        }
    }
}
