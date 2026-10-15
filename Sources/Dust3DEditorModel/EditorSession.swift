import Dust3DDocument
import Foundation

/// Serializes XML parsing and commands away from the UI actor. A window owns one session.
public actor EditorSession {
    private var state: EditorState?

    public init() {}

    public func open(data: Data) throws -> EditorSnapshot {
        try Task.checkCancellation()
        let next = try EditorState(document: Dust3DDocument(data: data))
        try Task.checkCancellation()
        state = next
        return next.snapshot
    }

    public func select(_ id: String?) throws -> EditorSnapshot { try update { try $0.select(id) } }

    public func edit(id: String, position: NodePosition, radius: Double) throws -> EditorSnapshot {
        try update { try $0.edit(id: id, position: position, radius: radius) }
    }

    /// Atomically apply a graph transaction; cancellation is checked before it begins.
    public func apply(_ commands: [DocumentCommand], selecting id: String? = nil) throws -> EditorSnapshot {
        try update { try $0.apply(commands, selecting: id) }
    }

    public func undo() throws -> EditorSnapshot { try update { try $0.undo() } }
    public func redo() throws -> EditorSnapshot { try update { try $0.redo() } }

    private func update(_ operation: (inout EditorState) throws -> Void) throws -> EditorSnapshot {
        try Task.checkCancellation()
        guard var next = state else { throw EditorError.notLoaded }
        try operation(&next)
        state = next
        return next.snapshot
    }
}
