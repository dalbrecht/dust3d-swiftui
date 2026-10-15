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

    /// Update this window's transient interaction lock state.
    public func setLock(_ constraint: EditingConstraint, isLocked: Bool) throws -> EditorSnapshot {
        try update { $0.setLock(constraint, isLocked: isLocked) }
    }

    public func select(_ id: String?) throws -> EditorSnapshot { try update { try $0.select(id) } }

    public func select(_ ids: Set<String>) throws -> EditorSnapshot { try update { try $0.select(ids) } }
    public func toggleSelection(_ id: String) throws -> EditorSnapshot { try update { try $0.toggleSelection(id) } }
    public func selectAll() throws -> EditorSnapshot { try update { $0.selectAll() } }
    public func moveSelection(by delta: NodePosition) throws -> EditorSnapshot {
        try update { try $0.moveSelection(by: delta) }
    }
    public func scaleSelection(positionFactor: Double, radiusFactor: Double) throws -> EditorSnapshot {
        try update { try $0.scaleSelection(positionFactor: positionFactor, radiusFactor: radiusFactor) }
    }
    public func transformSelection(_ transform: SelectionTransform) throws -> EditorSnapshot {
        try update { try $0.transformSelection(transform) }
    }
    public func reverseSelectedEdges() throws -> EditorSnapshot {
        try update { try $0.reverseSelectedEdges() }
    }
    public func move(id: String, to position: NodePosition) throws -> EditorSnapshot {
        try update { try $0.move(id: id, to: position) }
    }
    public func deleteSelection() throws -> EditorSnapshot {
        try update { state in
            let ids = state.snapshot.selectedNodes.filter(\.isEditable).map(\.id)
            let commands = try GraphCommandPreparation.normalizingDeletions(
                [.removeNodes(ids)], document: state.snapshot.document)
            try state.apply(commands)
        }
    }

    public func edit(id: String, position: NodePosition, radius: Double) throws -> EditorSnapshot {
        try update { try $0.edit(id: id, position: position, radius: radius) }
    }

    /// Atomically apply a graph transaction; cancellation is checked before it begins.
    public func apply(_ commands: [DocumentCommand], selecting id: String? = nil) throws -> EditorSnapshot {
        try update { state in
            let prepared = try GraphCommandPreparation.normalizingDeletions(commands, document: state.snapshot.document)
            try state.apply(prepared, selecting: id)
        }
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
