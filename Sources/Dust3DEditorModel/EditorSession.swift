import Dust3DDocument
import Foundation

/// Serializes XML parsing and commands away from the UI actor. A window owns one session.
public actor EditorSession {
    private var state: EditorState?
    private var lastPasteIdentifier: String?
    private var pasteOrdinal = 0

    public init() {}

    public func open(data: Data) throws -> EditorSnapshot {
        try Task.checkCancellation()
        let next = try EditorState(document: Dust3DDocument(data: data))
        try Task.checkCancellation()
        state = next
        lastPasteIdentifier = nil
        pasteOrdinal = 0
        return next.snapshot
    }

    /// Update this window's transient interaction lock state.
    public func setLock(_ constraint: EditingConstraint, isLocked: Bool) throws -> EditorSnapshot {
        try update { $0.setLock(constraint, isLocked: isLocked) }
    }

    public func select(_ id: String?) throws -> EditorSnapshot { try update { try $0.select(id) } }

    public func select(_ ids: Set<String>) throws -> EditorSnapshot { try update { try $0.select(ids) } }
    /// Select one edge without dirtying the document or creating an undo entry.
    public func selectEdge(_ id: String?) throws -> EditorSnapshot { try update { try $0.selectEdge(id) } }
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
            if let edge = state.snapshot.selectedEdge {
                guard state.snapshot.canEditSelectedEdge else { throw EditorError.readOnlyNode }
                let commands = try GraphCommandPreparation.normalizingDeletions(
                    [.removeEdge(id: edge.id)], document: state.snapshot.document)
                try state.apply(commands)
                return
            }
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

    /// Copy without dirtying the archive/history; Cut callers can restrict copying to editable nodes.
    /// - Parameter onlyEditable: Exclude read-only selected nodes when preparing a Cut.
    /// - Returns: A validated fragment including profile dependencies and all embedded assets.
    /// - Throws: `EditorError.notLoaded`, cancellation, or `DocumentError` for invalid/empty selection.
    public func copySelection(onlyEditable: Bool = false) throws -> NodeClipboard {
        try Task.checkCancellation()
        guard let state else { throw EditorError.notLoaded }
        let nodes = state.snapshot.selectedNodes.filter { !onlyEditable || $0.isEditable }
        let fragment = try state.snapshot.document.copyingNodes(Set(nodes.map(\.id)))
        try Task.checkCancellation()
        return fragment
    }

    /// Serialize off the UI actor; the platform boundary supplies the transient clipboard identifier.
    /// - Parameters:
    ///   - identifier: Fresh Copy/Cut token used for transient placement bookkeeping.
    ///   - onlyEditable: Restrict Cut payloads to editable selection.
    /// - Returns: Versioned native transport bytes.
    /// - Throws: Copy/transport validation errors without changing document, selection or history.
    public func copyPayload(identifier: String, onlyEditable: Bool = false) throws -> Data {
        try NodeClipboardPayload(fragment: copySelection(onlyEditable: onlyEditable), identifier: identifier).encoded()
    }

    /// Paste fresh graph identities and normalize copied groups in one undo transaction.
    /// Successive pastes move by 0.04 on Y/Z; placement bookkeeping is transient and resets on Open.
    /// - Parameter data: Bytes produced by `copyPayload(identifier:onlyEditable:)`.
    /// - Returns: The committed snapshot with only explicitly copied nodes selected.
    /// - Throws: Load, transport, archive or graph validation errors atomically; failed pastes do not advance placement.
    public func paste(data: Data) throws -> EditorSnapshot {
        try Task.checkCancellation()
        guard let state else { throw EditorError.notLoaded }
        let payload = try NodeClipboardPayload(data: data)
        let fragment = payload.fragment
        let sourceNodes = Set(try fragment.document.editorContents().nodes.map(\.id))
        let overlaps = !sourceNodes.isDisjoint(with: state.snapshot.nodes.map(\.id))
        let ordinal = lastPasteIdentifier == payload.identifier ? pasteOrdinal : (overlaps ? 1 : 0)
        let distance = Double(ordinal) * 0.04
        let identities = Dictionary(uniqueKeysWithValues: fragment.identifiers.map { ($0, Self.identifier()) })
        var partitions: [String: [PartSplitIdentity]] = [:]
        for requirement in try fragment.partSplitRequirements() {
            guard let partID = identities[requirement.partID] else { throw DocumentError.invalidNode }
            partitions[partID] = (0..<requirement.additionalPartCount).map { _ in
                PartSplitIdentity(
                    partID: Self.identifier(),
                    componentIDs: (0..<requirement.componentsPerPart).map { _ in Self.identifier() })
            }
        }
        let selected = Set(fragment.selectedNodeIDs.compactMap { identities[$0] })
        let next = try update { state in
            try state.apply([
                .pasteNodes(
                    clipboard: fragment, identities: identities,
                    offset: .init(x: 0, y: distance, z: distance), partitions: partitions)
            ])
            try state.select(selected)
        }
        lastPasteIdentifier = payload.identifier
        pasteOrdinal = ordinal + 1
        return next
    }

    private static func identifier() -> String { "{\(UUID().uuidString.lowercased())}" }

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
