import Dust3DDocument

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
            selectedID: selectedID, canUndo: history.canUndo, canRedo: history.canRedo,
            documentRevision: revision)
    }

    /// Select a node or clear selection; throws missingNode without changing state.
    public mutating func select(_ id: String?) throws {
        if let id, !contents.nodes.contains(where: { $0.id == id }) { throw DocumentError.missingNode(id) }
        selectedID = id
    }

    /// Commit one gesture or inspector edit as one undo step, respecting part locks/visibility.
    public mutating func edit(id: String, position: NodePosition, radius: Double) throws {
        guard let node = contents.nodes.first(where: { $0.id == id }) else { throw DocumentError.missingNode(id) }
        guard node.isEditable else { throw EditorError.readOnlyNode }
        var next = history
        try next.apply(.setNode(id: id, position: position, radius: radius))
        try publish(next)
        selectedID = id
    }

    /// Commit graph operations as one undo step. Failed batches preserve document and selection.
    /// The optional selection must exist in the resulting document.
    public mutating func apply(_ commands: [DocumentCommand], selecting id: String? = nil) throws {
        var next = history
        try next.beginTransaction()
        for command in commands {
            if case .setNode(let nodeID, _, _) = command {
                guard let node = try next.document.editorContents().nodes.first(where: { $0.id == nodeID }),
                    node.isEditable
                else {
                    throw EditorError.readOnlyNode
                }
            }
            try next.apply(command)
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

    private mutating func publish(_ next: DocumentHistory) throws {
        guard next.document.encoded() != history.document.encoded() else { return }
        let nextContents = try next.document.editorContents()
        contents = nextContents
        if let id = selectedID, !contents.nodes.contains(where: { $0.id == id }) { selectedID = nil }
        history = next
        revision += 1
    }
}
