import Dust3DDocument
import Foundation

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
    case invalidScale
    case invalidPivotSelection
    case unavailableOrigin
    case staleReferenceComposition
    case staleOriginDrag
}

/// Immutable presentation snapshot crossing from the editing actor to its window.
public struct EditorSnapshot: Sendable {
    /// Identity of this open document; revisions alone cannot distinguish replacements.
    public let documentIdentity: UUID
    public let document: Dust3DDocument
    public let nodes: [DocumentNode]
    public let edges: [DocumentEdge]
    public let parts: [DocumentPart]
    public let componentTree: ComponentTree
    /// All selected component identities, independent of graph selection and history.
    public let selectedComponentIDs: Set<String>
    /// A single component is inspectable only when the selection is unambiguous.
    public var selectedComponentID: String? { selectedComponentIDs.count == 1 ? selectedComponentIDs.first : nil }

    /// Selected rows in document order, including selected descendants hidden by a collapsed parent.
    public var selectedComponentRows: [ComponentTreeRow] {
        componentTree.rows.filter { selectedComponentIDs.contains($0.id) }
    }

    /// Grouping is available for nonempty siblings whose existing parent can accept edits.
    public var canGroupComponents: Bool {
        let selected = selectedComponentRows
        guard let first = selected.first,
            selected.allSatisfy({ $0.component.parentID == first.component.parentID })
        else { return false }
        guard let parent = first.component.parentID else { return true }
        return componentTree.rows.first { $0.id == parent }?.component.isGroup == true
    }
    /// Only a single supported group with retained child XML can be ungrouped.
    public var canUngroupComponent: Bool {
        guard let component = selectedComponent, component.isGroup, component.hasChildXML else { return false }
        guard let parent = component.parentID else { return true }
        return componentTree.rows.first { $0.id == parent }?.component.isGroup == true
    }
    /// Complete supported canvas origin, independent of selection.
    public let origin: NodePosition?
    public let selectedID: String?
    public let selectedIDs: Set<String>
    public let selectedEdgeID: String?
    public let selectedPartID: String?
    public let canUndo: Bool
    public let canRedo: Bool
    public let locks: Set<EditingConstraint>
    public let documentRevision: Int
    /// Monotonic interaction epoch, including lock toggles that later restore the same values.
    public let constraintRevision: Int

    /// Descendant rotation needs a single editable pivot and an explicit supported origin.
    public var canRotateDescendants: Bool {
        selectedIDs.count == 1 && selectedNode?.isEditable == true && origin != nil
    }

    public var selectedNodes: [DocumentNode] { nodes.filter { selectedIDs.contains($0.id) } }
    public var selectedNode: DocumentNode? { nodes.first { $0.id == selectedID } }
    /// A single edge is selected independently of nodes, without changing document history.
    public var selectedEdge: DocumentEdge? { edges.first { $0.id == selectedEdgeID } }
    /// A selected part remains inspectable even when hidden, locked or disabled.
    /// Non-no-op sibling-order commands for the current component selection.
    public var availableComponentOrderMoves: [ComponentOrderMove] {
        selectedComponentID.map { componentTree.orderMoves(for: $0) } ?? []
    }
    public var selectedComponent: DocumentComponent? {
        componentTree.rows.first { $0.id == selectedComponentID }?.component
    }
    public var selectedPart: DocumentPart? { parts.first { $0.id == selectedPartID } }
    /// Visibility is an editing option; only disabled parts suppress generated geometry.
    public var hasEnabledGeometry: Bool {
        let disabled = Set(parts.filter(\.isDisabled).map(\.id))
        return nodes.contains { node in node.partID.map { !disabled.contains($0) } ?? true }
    }
    /// Both endpoints must be editable before the selected edge can be changed.
    public var canEditSelectedEdge: Bool {
        guard let selectedEdgeID else { return false }
        return editableEdges.contains { $0.id == selectedEdgeID }
    }
    /// Copy can include read-only nodes, but every copied node must belong to a part.
    public var canCopyNodes: Bool {
        let selected = selectedNodes
        return !selected.isEmpty && selected.allSatisfy { $0.partID != nil }
    }
    /// Cut copies/removes only editable selection; read-only nodes remain selected and unchanged.
    public var canCutNodes: Bool {
        let editable = selectedNodes.filter(\.isEditable)
        return !editable.isEmpty && editable.allSatisfy { $0.partID != nil }
    }
    /// Edges whose endpoints both belong to editable parts, independent of selection.
    public var editableEdges: [DocumentEdge] {
        let editable = Set(nodes.filter(\.isEditable).map(\.id))
        return edges.filter { editable.contains($0.fromID) && editable.contains($0.toID) }
    }
    /// Editable edges entirely inside the selected node set.
    public var reversibleEdges: [DocumentEdge] {
        editableEdges.filter { selectedIDs.contains($0.fromID) && selectedIDs.contains($0.toID) }
    }
    /// Editable assigned nodes with room for another edge, matching Qt's endpoint rule.
    public var connectableNodes: [DocumentNode] {
        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.fromID, default: 0] += 1
            degree[edge.toID, default: 0] += 1
        }
        return nodes.filter { $0.isEditable && $0.partID != nil && (degree[$0.id] ?? 0) < 2 }
    }
    /// Empty selection creates a part; one editable endpoint extends it. Groups need an explicit New Part.
    public var canAddNode: Bool {
        guard selectedComponentIDs.isEmpty, selectedPartID == nil, selectedEdgeID == nil, selectedIDs.count <= 1 else {
            return false
        }
        guard let selected = selectedNode else { return true }
        return selected.isEditable && (selected.partID == nil || connectableNodes.contains { $0.id == selected.id })
    }
    /// Place a new node a quarter unit away from the existing neighbor, or along Y for a lone node.
    public var nextNodePosition: NodePosition {
        guard let selected = selectedNode else { return .init(x: 0.5, y: 0.5, z: 0.5) }
        let position = selected.value.position
        if let edge = edges.first(where: { $0.fromID == selected.id || $0.toID == selected.id }),
            let neighbor = nodes.first(where: { $0.id == (edge.fromID == selected.id ? edge.toID : edge.fromID) })
        {
            let x = position.x - neighbor.value.position.x
            let y = position.y - neighbor.value.position.y
            let z = position.z - neighbor.value.position.z
            let length = (x * x + y * y + z * z).squareRoot()
            if length > 0 {
                return .init(
                    x: position.x + x / length * 0.25, y: position.y + y / length * 0.25,
                    z: position.z + z / length * 0.25)
            }
        }
        return .init(x: position.x, y: position.y + 0.25, z: position.z)
    }
    /// Available endpoint targets, including other parts. Duplicate/self links are excluded.
    public var connectionTargets: [DocumentNode] {
        guard selectedIDs.count == 1, let selected = selectedNode else { return [] }
        let endpoints = connectableNodes
        guard endpoints.contains(where: { $0.id == selected.id }) else { return [] }
        let neighbors = Set(
            edges.compactMap { edge -> String? in
                if edge.fromID == selected.id { return edge.toID }
                if edge.toID == selected.id { return edge.fromID }
                return nil
            })
        return endpoints.filter { $0.id != selected.id && !neighbors.contains($0.id) }
    }

}

/// One document's selection and undo state. Failed edits never publish partial state.
public struct EditorState: Sendable {
    private let documentIdentity = UUID()
    private var history: DocumentHistory
    private var contents: DocumentContents
    private var componentTree: ComponentTree
    private var selectedComponentIDs: Set<String> = []
    private var selectedID: String?
    private var selectedIDs: Set<String> = []
    private var selectedEdgeID: String?
    private var selectedPartID: String?
    private var locks: Set<EditingConstraint> = []
    private var revision = 0
    private var constraintRevision = 0

    /// Parse graph metadata. Throws DocumentError for invalid or oversized graphs.
    public init(document: Dust3DDocument) throws {
        contents = try document.editorContents()
        componentTree = ComponentTree(document: document)
        history = DocumentHistory(document: document)
    }

    /// Current immutable document, graph, selection and history availability.
    public var snapshot: EditorSnapshot {
        EditorSnapshot(
            documentIdentity: documentIdentity, document: history.document, nodes: contents.nodes,
            edges: contents.edges, parts: contents.parts,
            componentTree: componentTree, selectedComponentIDs: selectedComponentIDs,
            origin: contents.origin,
            selectedID: selectedID, selectedIDs: selectedIDs, selectedEdgeID: selectedEdgeID,
            selectedPartID: selectedPartID,
            canUndo: history.canUndo, canRedo: history.canRedo,
            locks: locks,
            documentRevision: revision, constraintRevision: constraintRevision)
    }

    /// Select a single node or clear the transient selection.
    public mutating func select(_ id: String?) throws {
        try select(id.map { Set([$0]) } ?? [])
    }

    /// Replace selection atomically; primary selection follows document order.
    public mutating func select(_ ids: Set<String>) throws {
        let existing = Set(contents.nodes.map(\.id))
        if let missing = ids.subtracting(existing).sorted().first { throw DocumentError.missingNode(missing) }
        selectedIDs = ids
        selectedID = contents.nodes.first { ids.contains($0.id) }?.id
        selectedEdgeID = nil
        selectedPartID = nil
        selectedComponentIDs = []
    }

    /// Inspect an existing edge or clear selection. Invalid IDs throw DocumentError.invalidNode atomically.
    public mutating func selectEdge(_ id: String?) throws {
        if let id, !contents.edges.contains(where: { $0.id == id }) { throw DocumentError.invalidNode }
        selectedEdgeID = id
        selectedPartID = nil
        selectedComponentIDs = []
        selectedID = nil
        selectedIDs = []
    }

    /// Inspect an existing part or clear selection. Missing IDs throw DocumentError.missingPart atomically.
    public mutating func selectPart(_ id: String?) throws {
        if let id, !contents.parts.contains(where: { $0.id == id }) { throw DocumentError.missingPart(id) }
        selectedPartID = id
        selectedComponentIDs = []
        selectedEdgeID = nil
        selectedID = nil
        selectedIDs = []
    }

    /// Inspect a component without changing archive bytes or undo history.
    /// - Parameter id: Existing component ID, or nil to clear all selections.
    /// - Throws: `DocumentError.missingComponent` for absent or uninterpretable identities, atomically.
    public mutating func selectComponent(_ id: String?) throws {
        try selectComponents(id.map { [$0] } ?? [])
    }

    /// Replace component selection atomically without modifying document bytes, revision or history.
    /// - Parameter ids: Existing component identities; empty clears every selection category.
    /// - Throws: `DocumentError.missingComponent` before publication for any missing identity.
    public mutating func selectComponents(_ ids: Set<String>) throws {
        let existing = Set(componentTree.rows.map(\.id))
        if let missing = ids.subtracting(existing).sorted().first { throw DocumentError.missingComponent(missing) }
        selectedComponentIDs = ids
        selectedPartID = nil
        selectedEdgeID = nil
        selectedID = nil
        selectedIDs = []
    }

    /// Toggle a node without modifying document data or history.
    public mutating func toggleSelection(_ id: String) throws {
        var next = selectedIDs
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        try select(next)
    }

    /// Include all nodes, including read-only nodes for inspection.
    public mutating func selectAll() {
        selectedEdgeID = nil
        selectedPartID = nil
        selectedComponentIDs = []
        selectedIDs = Set(contents.nodes.map(\.id))
        selectedID = contents.nodes.first?.id
    }

    /// Translate editable selected nodes as one atomic undo step. Read-only nodes stay fixed.
    public mutating func moveSelection(by delta: NodePosition) throws {
        guard [delta.x, delta.y, delta.z].allSatisfy(\.isFinite) else { throw DocumentError.invalidNode }
        let updates = snapshot.selectedNodes.filter(\.isEditable).map { node in
            let position = node.value.position
            return NodeUpdate(
                id: node.id,
                value: .init(
                    position: .init(x: position.x + delta.x, y: position.y + delta.y, z: position.z + delta.z),
                    radius: node.value.radius))
        }
        try apply([.setNodes(updates)])
    }

    /// Scale editable node positions about their centroid and radii independently.
    /// Factors must be finite and positive. Locks and read-only parts retain their values.
    public mutating func scaleSelection(positionFactor: Double, radiusFactor: Double) throws {
        guard positionFactor.isFinite, radiusFactor.isFinite, positionFactor > 0, radiusFactor > 0 else {
            throw EditorError.invalidScale
        }
        let nodes = snapshot.selectedNodes.filter(\.isEditable)
        guard !nodes.isEmpty else { return }
        let count = Double(nodes.count)
        let center = NodePosition(
            x: nodes.reduce(0) { $0 + $1.value.position.x } / count,
            y: nodes.reduce(0) { $0 + $1.value.position.y } / count,
            z: nodes.reduce(0) { $0 + $1.value.position.z } / count)
        let updates = nodes.map { node in
            let position = node.value.position
            return NodeUpdate(
                id: node.id,
                value: .init(
                    position: positionFactor == 1
                        ? position
                        : .init(
                            x: locks.contains(.x) ? position.x : center.x + (position.x - center.x) * positionFactor,
                            y: locks.contains(.y) ? position.y : center.y + (position.y - center.y) * positionFactor,
                            z: locks.contains(.z) ? position.z : center.z + (position.z - center.z) * positionFactor),
                    radius: locks.contains(.radius) ? node.value.radius : node.value.radius * radiusFactor))
        }
        try apply([.setNodes(updates)])
    }

    /// Apply a prepared PNG and optional proposed origin as one undo transaction.
    /// - Parameters:
    ///   - png: Bounded PNG bytes prepared by the platform raster boundary.
    ///   - origin: Optional image-relative origin; native axis locks apply. Nil retains the stored origin.
    ///   - target: Captured document and constraint epochs; stale drafts cannot overwrite later edits.
    /// - Throws: Typed stale-draft or document validation errors atomically.
    public mutating func applyReferenceComposition(
        png: Data, origin: NodePosition?, target: ReferenceCompositionTarget
    ) throws {
        guard target.documentIdentity == documentIdentity, target.documentRevision == revision,
            target.constraintRevision == constraintRevision
        else { throw EditorError.staleReferenceComposition }
        var commands: [DocumentCommand] = [.setReferenceImagePNG(png)]
        if let origin { commands.append(.setOrigin(origin)) }
        try apply(commands)
    }

    /// Rotate editable connected descendants around the single selected pivot in one undo step.
    /// The neighbor nearest the stored origin is the parent; endpoints rotate their whole connected chain.
    /// Axis/part locks apply. Throws typed selection/origin/readonly or geometry errors atomically.
    public mutating func rotateDescendants(_ rotation: DescendantRotation) throws {
        guard selectedIDs.count == 1, let pivot = snapshot.selectedNode else { throw EditorError.invalidPivotSelection }
        guard pivot.isEditable else { throw EditorError.readOnlyNode }
        guard let origin = contents.origin else { throw EditorError.unavailableOrigin }
        let ids = rotation.descendantIDs(pivot: pivot, origin: origin, nodes: contents.nodes, edges: contents.edges)
        let updates = contents.nodes.filter { ids.contains($0.id) && $0.id != pivot.id && $0.isEditable }.map { node in
            NodeUpdate(
                id: node.id,
                value: .init(
                    position: rotation.transform.position(node.value.position, around: pivot.value.position),
                    radius: node.value.radius))
        }
        try apply([.setNodes(updates)])
    }

    /// Apply a basic transform as one atomic undo step, retaining selection and radii.
    public mutating func transformSelection(_ transform: SelectionTransform) throws {
        let nodes = snapshot.selectedNodes.filter(\.isEditable)
        guard !nodes.isEmpty else { return }
        let count = Double(nodes.count)
        let center: NodePosition
        if transform.usesOrigin {
            guard let origin = contents.origin else { throw EditorError.unavailableOrigin }
            center = origin
        } else {
            center = NodePosition(
                x: nodes.reduce(0) { $0 + $1.value.position.x } / count,
                y: nodes.reduce(0) { $0 + $1.value.position.y } / count,
                z: nodes.reduce(0) { $0 + $1.value.position.z } / count)
        }
        let updates = nodes.map { node in
            let original = node.value.position
            let proposed = transform.position(original, around: center)
            let position =
                transform == .exchangeXZ
                ? proposed
                : NodePosition(
                    x: locks.contains(.x) ? original.x : proposed.x,
                    y: locks.contains(.y) ? original.y : proposed.y,
                    z: locks.contains(.z) ? original.z : proposed.z)
            return NodeUpdate(id: node.id, value: .init(position: position, radius: node.value.radius))
        }
        if transform == .exchangeXZ {
            // Qt's switchNodeXZ exchanges coordinates directly without movement locks.
            var next = history
            try next.apply(.setNodes(updates))
            try publish(next)
        } else {
            try apply([.setNodes(updates)])
        }
    }

    /// Reverse edges whose endpoints are both selected and editable, as one undo step.
    public mutating func reverseSelectedEdges() throws {
        try apply([.reverseEdges(snapshot.reversibleEdges.map(\.id))])
    }

    /// Drag an anchor, retaining its group if selected; otherwise select only the anchor.
    public mutating func move(id: String, to position: NodePosition) throws {
        guard let node = contents.nodes.first(where: { $0.id == id }) else { throw DocumentError.missingNode(id) }
        guard node.isEditable else { throw EditorError.readOnlyNode }
        var next = self
        if !selectedIDs.contains(id) { try next.select(id) }
        let original = node.value.position
        try next.moveSelection(
            by: .init(x: position.x - original.x, y: position.y - original.y, z: position.z - original.z))
        self = next
    }

    /// Low-level deletion without allocating identities. App callers use EditorSession.deleteSelection,
    /// which composes explicit split commands with removal in the same undo transaction.
    public mutating func deleteSelection() throws {
        if let edge = snapshot.selectedEdge {
            guard snapshot.canEditSelectedEdge else { throw EditorError.readOnlyNode }
            try apply([.removeEdge(id: edge.id)])
            return
        }
        try apply([.removeNodes(snapshot.selectedNodes.filter(\.isEditable).map(\.id))])
    }

    /// Change an interaction lock without dirtying the document or changing history.
    public mutating func setLock(_ constraint: EditingConstraint, isLocked: Bool) {
        constraintRevision += 1
        if isLocked { locks.insert(constraint) } else { locks.remove(constraint) }
    }

    /// Center the origin on every node's radius bounds in one undo step, respecting axis locks.
    /// Empty models target zero. Unavailable origins require unlocked position axes.
    /// Throws geometry/origin validation errors atomically; nodes, selection and assets stay unchanged.
    public mutating func centerOriginOnModel() throws {
        let position = try OriginSettlement.center(of: contents.nodes.map(\.value))
        try apply([.setOrigin(position)])
    }

    /// Commit one gesture or inspector edit as one undo step, respecting part locks/visibility.
    public mutating func edit(id: String, position: NodePosition, radius: Double) throws {
        var next = history
        try next.apply(constrainedNode(id: id, value: .init(position: position, radius: radius), nodes: contents.nodes))
        try publish(next)
        try select(id)
    }

    /// Commit graph operations as one undo step. Failed batches preserve document and selection.
    /// The optional selection must exist in the resulting document.
    public mutating func apply(_ commands: [DocumentCommand], selecting id: String? = nil) throws {
        var next = history
        try next.beginTransaction()
        for command in commands {
            switch command {
            case .setOrigin(let position):
                guard [position.x, position.y, position.z].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
                    throw DocumentError.invalidOrigin
                }
                if let origin = try next.document.origin() {
                    try next.apply(
                        .setOrigin(
                            .init(
                                x: locks.contains(.x) ? origin.x : position.x,
                                y: locks.contains(.y) ? origin.y : position.y,
                                z: locks.contains(.z) ? origin.z : position.z)))
                } else {
                    guard locks.isDisjoint(with: [.x, .y, .z]) else { throw EditorError.unavailableOrigin }
                    try next.apply(command)
                }
            case .setNode(let id, let position, let radius):
                let nodes = try next.document.editorContents().nodes
                try next.apply(constrainedNode(id: id, value: .init(position: position, radius: radius), nodes: nodes))
            case .setNodes(let updates):
                let nodes = Dictionary(
                    uniqueKeysWithValues: try next.document.editorContents().nodes.map { ($0.id, $0) })
                let constrained = try updates.map { update -> NodeUpdate in
                    let value = try constrainedValue(id: update.id, value: update.value, nodes: nodes)
                    return NodeUpdate(id: update.id, value: value)
                }
                try next.apply(.setNodes(constrained))
            default: try next.apply(command)
            }
        }
        try next.endTransaction()
        if let id, !(try next.document.editorContents().nodes.contains(where: { $0.id == id })) {
            throw DocumentError.missingNode(id)
        }
        try publish(next)
        if let id { try select(id) }
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
        let value = try constrainedValue(
            id: id, value: value, nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }))
        return .setNode(id: id, position: value.position, radius: value.radius)
    }

    private func constrainedValue(id: String, value: EditableNode, nodes: [String: DocumentNode]) throws -> EditableNode
    {
        guard let node = nodes[id] else { throw DocumentError.missingNode(id) }
        guard node.isEditable else { throw EditorError.readOnlyNode }
        guard value.isValid else { throw DocumentError.invalidNode }
        let original = node.value
        return EditableNode(
            position: .init(
                x: locks.contains(.x) ? original.position.x : value.position.x,
                y: locks.contains(.y) ? original.position.y : value.position.y,
                z: locks.contains(.z) ? original.position.z : value.position.z),
            radius: locks.contains(.radius) ? original.radius : value.radius)
    }

    private mutating func publish(_ next: DocumentHistory) throws {
        guard next.document.encoded() != history.document.encoded() else { return }
        let nextContents = try next.document.editorContents()
        let nextTree = ComponentTree(document: next.document)
        contents = nextContents
        componentTree = nextTree
        selectedComponentIDs.formIntersection(nextTree.rows.map(\.id))
        selectedIDs.formIntersection(contents.nodes.map(\.id))
        selectedID = contents.nodes.first { selectedIDs.contains($0.id) }?.id
        if let selectedEdgeID, !contents.edges.contains(where: { $0.id == selectedEdgeID }) {
            self.selectedEdgeID = nil
        }
        if let selectedPartID, !contents.parts.contains(where: { $0.id == selectedPartID }) {
            self.selectedPartID = nil
        }
        history = next
        revision += 1
    }
}
