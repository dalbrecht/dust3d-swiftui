import Dust3DDocument

/// Per-window interaction constraints. These settings never enter the archive or undo history.
public enum EditingConstraint: String, CaseIterable, Sendable {
    case x = "X"
    case y = "Y"
    case z = "Z"
    case radius = "Radius"
}

/// Typed editing boundary failures; malformed archive and node errors use DocumentError.
public enum EditorError: Error, Equatable, Sendable {
    case notLoaded
    case readOnlyNode
}

/// Immutable presentation snapshot crossing from the editing actor to its window.
public struct EditorSnapshot: Sendable {
    public let document: Dust3DDocument
    public let nodes: [DocumentNode]
    public let edges: [DocumentEdge]
    public let selectedID: String?
    public let canUndo: Bool
    public let canRedo: Bool
    public let locks: Set<EditingConstraint>
    public let documentRevision: Int

    public var selectedNode: DocumentNode? { nodes.first { $0.id == selectedID } }
    /// Editable same-part nodes that are not already joined to the current selection.
    public var connectionTargets: [DocumentNode] {
        guard let selected = selectedNode, selected.isEditable, let partID = selected.partID else { return [] }
        let neighbors = Set(
            edges.compactMap { edge -> String? in
                if edge.fromID == selected.id { return edge.toID }
                if edge.toID == selected.id { return edge.fromID }
                return nil
            })
        return nodes.filter {
            $0.id != selected.id && $0.isEditable && $0.partID == partID && !neighbors.contains($0.id)
        }
    }

}

/// One document's selection and undo state. Failed edits never publish partial state.
public struct EditorState: Sendable {
    private var history: DocumentHistory
    private var contents: DocumentContents
    private var selectedID: String?
    private var locks: Set<EditingConstraint> = []
    private var revision = 0

    /// Parse graph metadata. Throws DocumentError for invalid or oversized graphs.
    public init(document: Dust3DDocument) throws {
        contents = try document.editorContents()
        history = DocumentHistory(document: document)
    }

    /// Current immutable document, graph, selection and history availability.
    public var snapshot: EditorSnapshot {
        EditorSnapshot(
            document: history.document, nodes: contents.nodes, edges: contents.edges,
            selectedID: selectedID, canUndo: history.canUndo, canRedo: history.canRedo, locks: locks,
            documentRevision: revision)
    }

    /// Select a node or clear selection; throws missingNode without changing state.
    public mutating func select(_ id: String?) throws {
        if let id, !contents.nodes.contains(where: { $0.id == id }) { throw DocumentError.missingNode(id) }
        selectedID = id
    }

    /// Change an interaction lock without dirtying the document or changing history.
    public mutating func setLock(_ constraint: EditingConstraint, isLocked: Bool) {
        if isLocked { locks.insert(constraint) } else { locks.remove(constraint) }
    }

    /// Commit one gesture or inspector edit as one undo step, respecting part locks/visibility.
    public mutating func edit(id: String, position: NodePosition, radius: Double) throws {
        var next = history
        try next.apply(constrainedNode(id: id, value: .init(position: position, radius: radius), nodes: contents.nodes))
        try publish(next)
        selectedID = id
    }

    /// Commit graph operations as one undo step. Failed batches preserve document and selection.
    /// The optional selection must exist in the resulting document.
    public mutating func apply(_ commands: [DocumentCommand], selecting id: String? = nil) throws {
        var next = history
        try next.beginTransaction()
        for command in commands {
            switch command {
            case .setNode(let id, let position, let radius):
                let nodes = try next.document.editorContents().nodes
                try next.apply(constrainedNode(id: id, value: .init(position: position, radius: radius), nodes: nodes))
            default: try next.apply(command)
            }
        }
        try next.endTransaction()
        if let id, !(try next.document.editorContents().nodes.contains(where: { $0.id == id })) {
            throw DocumentError.missingNode(id)
        }
        try publish(next)
        if let id { selectedID = id }
    }

    /// Restore the previous archive, if available, retaining transient selection.
    public mutating func undo() throws {
        var next = history
        if next.undo() { try publish(next) }
    }

    /// Reapply the next archive, if available, retaining transient selection.
    public mutating func redo() throws {
        var next = history
        if next.redo() { try publish(next) }
    }

    private func constrainedNode(id: String, value: EditableNode, nodes: [DocumentNode]) throws -> DocumentCommand {
        guard let node = nodes.first(where: { $0.id == id }) else { throw DocumentError.missingNode(id) }
        guard node.isEditable else { throw EditorError.readOnlyNode }
        guard value.isValid else { throw DocumentError.invalidNode }
        let original = node.value
        return .setNode(
            id: id,
            position: .init(
                x: locks.contains(.x) ? original.position.x : value.position.x,
                y: locks.contains(.y) ? original.position.y : value.position.y,
                z: locks.contains(.z) ? original.position.z : value.position.z),
            radius: locks.contains(.radius) ? original.radius : value.radius)
    }

    private mutating func publish(_ next: DocumentHistory) throws {
        guard next.document.encoded() != history.document.encoded() else { return }
        let nextContents = try next.document.editorContents()
        contents = nextContents
        if let id = selectedID, !contents.nodes.contains(where: { $0.id == id }) { selectedID = nil }
        history = next
        revision += 1
    }
}
