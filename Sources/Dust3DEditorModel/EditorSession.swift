import Dust3DDocument
import Foundation

/// Serializes XML parsing and commands away from the UI actor. A window owns one session.
public actor EditorSession {
    private var state: EditorState?
    private var lastPasteIdentifier: String?
    private var pasteOrdinal = 0
    private var lastQtTransfer: (snapshot: Data, identifier: String)?

    public init() {}

    public func open(data: Data) throws -> EditorSnapshot {
        try Task.checkCancellation()
        let next = try EditorState(document: Dust3DDocument(data: data))
        try Task.checkCancellation()
        state = next
        lastPasteIdentifier = nil
        pasteOrdinal = 0
        lastQtTransfer = nil
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
    /// Inspect a part without changing document bytes or undo history.
    /// Wrap explicit sibling identities in a fresh group and inspect that group in one atomic publication.
    /// - Parameter ids: Nonempty sibling identities; source order is retained independent of Set iteration.
    /// - Returns: One undoable snapshot with a fresh UUID component selected.
    /// - Throws: Load/cancellation, hierarchy, identity or bounded-archive errors without partial state.
    public func groupComponents(_ ids: Set<String>) throws -> EditorSnapshot {
        try update { state in
            let groupID = Self.identifier()
            try state.apply([.groupComponents(ids: ids.sorted(), groupID: groupID)])
            try state.selectComponent(groupID)
        }
    }

    /// Inspect a component independently of nodes, edges and parts; selection is window-local.
    public func selectComponent(_ id: String?) throws -> EditorSnapshot {
        try update { try $0.selectComponent(id) }
    }
    /// Replace window-local component selection without creating an undo entry.
    /// - Parameter ids: Existing component identities, or empty to clear selection.
    /// - Returns: The unchanged document with its new exclusive component selection.
    /// - Throws: Load, cancellation or missing-component errors atomically.
    public func selectComponents(_ ids: Set<String>) throws -> EditorSnapshot {
        try update { try $0.selectComponents(ids) }
    }
    /// Move a captured selected subtree to an explicit root/group destination atomically.
    /// - Parameters:
    ///   - parent: Requested destination; hierarchy and cycles are revalidated before publication.
    ///   - target: Captured selected component and document epoch.
    /// - Returns: One undoable document snapshot with the moved subtree still selected.
    /// - Throws: Load, cancellation, stale-target or typed document errors without partial state.
    public func reparentComponent(to parent: ComponentParent, target: ComponentReparentTarget) throws -> EditorSnapshot
    {
        try update { try $0.reparentComponent(to: parent, target: target) }
    }
    public func selectPart(_ id: String?) throws -> EditorSnapshot { try update { try $0.selectPart(id) } }
    public func toggleSelection(_ id: String) throws -> EditorSnapshot { try update { try $0.toggleSelection(id) } }
    public func selectAll() throws -> EditorSnapshot { try update { $0.selectAll() } }
    /// Explicitly center origin on all node radius bounds, honoring axis locks in one history transaction.
    /// - Returns: The committed snapshot, or unchanged history for an already-centered origin.
    /// - Throws: Load, cancellation, geometry or unavailable-origin errors without partial publication.
    public func centerOriginOnModel() throws -> EditorSnapshot {
        try update { try $0.centerOriginOnModel() }
    }
    public func moveSelection(by delta: NodePosition) throws -> EditorSnapshot {
        try update { try $0.moveSelection(by: delta) }
    }
    public func scaleSelection(positionFactor: Double, radiusFactor: Double) throws -> EditorSnapshot {
        try update { try $0.scaleSelection(positionFactor: positionFactor, radiusFactor: radiusFactor) }
    }
    /// Commit prepared reference composition output to its captured target in one undo step.
    /// - Parameters:
    ///   - png: Platform-validated bounded PNG data.
    ///   - origin: Optional proposed origin; native axis locks apply.
    ///   - target: Document and constraint epochs captured when the draft opened.
    /// - Returns: Committed snapshot, or unchanged history for identical output.
    /// - Throws: Load, cancellation, stale-draft or document validation errors atomically.
    public func applyReferenceComposition(
        png: Data, origin: NodePosition?, target: ReferenceCompositionTarget
    ) throws -> EditorSnapshot {
        try update { try $0.applyReferenceComposition(png: png, origin: origin, target: target) }
    }

    /// Rotate connected descendants around the selected pivot without changing selection or radii.
    /// - Parameter rotation: Explicit Front/Side quarter-turn direction.
    /// - Returns: One undoable snapshot, or unchanged history for a no-op.
    /// - Throws: Load, cancellation, selection/origin/readonly or geometry validation errors atomically.
    public func rotateDescendants(_ rotation: DescendantRotation) throws -> EditorSnapshot {
        try update { try $0.rotateDescendants(rotation) }
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

    /// Commit a projected origin gesture only while its document, revision and locks still match.
    /// - Parameters:
    ///   - drag: Immutable baseline captured at gesture start, including its fixed projection.
    ///   - translation: Total screen-point displacement from that start.
    /// - Returns: One undoable origin edit, or the unchanged snapshot for a no-op.
    /// - Throws: `EditorError.staleOriginDrag`, load/cancellation errors, or invalid-origin errors atomically.
    public func commitOriginDrag(_ drag: OriginDrag, translation: CanvasPoint) throws -> EditorSnapshot {
        try update { state in
            guard drag.isCurrent(in: state.snapshot) else { throw EditorError.staleOriginDrag }
            guard translation.x.isFinite, translation.y.isFinite else { throw DocumentError.invalidOrigin }
            try state.apply([.setOrigin(drag.position(by: translation))])
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

    /// Produce rich native bytes and an asset-free Qt text fallback off the UI actor.
    /// - Parameters:
    ///   - identifier: Fresh Copy/Cut token.
    ///   - onlyEditable: Limit Cut to editable selected nodes.
    /// - Returns: Native transport plus exact UTF-8 canvas XML. Only native bytes carry assets/selection metadata.
    /// - Throws: Copy and transport validation errors without mutating the document.
    public func copyRepresentations(identifier: String, onlyEditable: Bool = false) throws -> (
        native: Data, snapshotXML: Data
    ) {
        let payload = try NodeClipboardPayload(
            fragment: copySelection(onlyEditable: onlyEditable), identifier: identifier)
        return (try payload.encoded(), payload.fragment.document.modelXML)
    }

    /// Paste Qt canvas XML through the same graph transaction as native transfers.
    /// - Parameter snapshotXML: Bounded asset-free Qt text; all imported nodes become selected.
    /// - Returns: A snapshot with one undo step; identical successful text advances per-window placement.
    /// - Throws: Typed validation/load errors atomically; failed text does not advance placement bookkeeping.
    public func paste(snapshotXML: Data) throws -> EditorSnapshot {
        try Task.checkCancellation()
        guard state != nil else { throw EditorError.notLoaded }
        let identifier: String
        if let previous = lastQtTransfer, previous.snapshot == snapshotXML {
            identifier = previous.identifier
        } else {
            identifier = Self.identifier()
        }
        let payload = try NodeClipboardPayload(snapshotXML: snapshotXML, identifier: identifier)
        let next = try paste(payload: payload)
        lastQtTransfer = (Data(snapshotXML), identifier)
        return next
    }

    /// Paste fresh graph identities and normalize copied groups in one undo transaction.
    /// Successive pastes move by 0.04 on Y/Z; placement bookkeeping is transient and resets on Open.
    /// - Parameter data: Bytes produced by `copyPayload(identifier:onlyEditable:)`.
    /// - Returns: The committed snapshot with only explicitly copied nodes selected.
    /// - Throws: Load, transport, archive or graph validation errors atomically; failed pastes do not advance placement.
    public func paste(data: Data) throws -> EditorSnapshot {
        try Task.checkCancellation()
        guard state != nil else { throw EditorError.notLoaded }
        return try paste(payload: NodeClipboardPayload(data: data))
    }

    private func paste(payload: NodeClipboardPayload) throws -> EditorSnapshot {
        guard let state else { throw EditorError.notLoaded }
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
