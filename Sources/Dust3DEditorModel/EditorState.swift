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
    case invalidSpacingFactor
    case invalidRotation
    case invalidPivotSelection
    case unavailableOrigin
    case staleReferenceComposition
    case staleReferenceColor
    case invalidReferenceColorSelection
    case staleComponentMove
    case staleColorImageTarget
    case staleOriginDrag
    case staleNodeDrag
    case staleCanvasAdjustment
    case staleAddPlacement
    case stalePartGraphSelection
    case invalidAddPlacement
    case staleExport
    case staleAnimationTarget
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
    /// Parsed on the editing actor; stored intent does not imply native rig generation support.
    public let rigSettings: DocumentRigSettings
    /// Materialized off the UI actor, without copying image payloads.
    public let colorImageAssets: [DocumentColorImageAsset]
    /// All selected component identities, independent of graph selection and history.
    public let selectedComponentIDs: Set<String>
    /// Scroll/expand association for the last whole-part action, without selecting the owning component.
    public let componentRevealHint: ComponentRevealHint?
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
    /// Explicit selected edges, independent of explicit selected node identities.
    public let selectedEdgeIDs: Set<String>
    /// Compatibility accessor for exactly one explicit edge.
    public var selectedEdgeID: String? { selectedEdgeIDs.count == 1 ? selectedEdgeIDs.first : nil }
    /// Full batch midpoint eligibility, including the aggregate graph quota.
    public let canInsertSelectedEdgeMidpoints: Bool
    /// Compatibility accessor for a single editable edge.
    public var canInsertSelectedEdgeMidpoint: Bool { selectedEdgeIDs.count == 1 && canInsertSelectedEdgeMidpoints }
    /// Validated by the editing session for the current explicit node selection.
    public let canReduceSelectedNodes: Bool
    public let selectedPartID: String?
    public let canUndo: Bool
    public let canRedo: Bool
    public let locks: Set<EditingConstraint>
    public let documentRevision: Int
    /// Trusted geometry/material input identities restored with accepted document history.
    public let previewIdentity: DocumentPreviewIdentity
    /// Monotonic interaction epoch, including lock toggles that later restore the same values.
    public let constraintRevision: Int
    /// Monotonic epoch for changes to the transient selection.
    public let selectionRevision: Int

    /// Descendant rotation needs a single editable pivot and an explicit supported origin.
    public var canRotateDescendants: Bool {
        selectedIDs.count == 1 && selectedNode?.isEditable == true && origin != nil
    }

    public var selectedNodes: [DocumentNode] { nodes.filter { selectedIDs.contains($0.id) } }
    public var selectedNode: DocumentNode? { nodes.first { $0.id == selectedID } }

    package func allowsNodeDeformation(for nodeID: String) -> Bool {
        guard selectedIDs.count == 1, selectedEdgeIDs.isEmpty, let node = selectedNode, node.isEditable,
            node.id.utf8.elementsEqual(nodeID.utf8), let partID = node.partID
        else { return false }
        return parts.first(where: { $0.id.utf8.elementsEqual(partID.utf8) })?.target == .model
    }
    /// Explicit edges in archive presentation order; this never infers edges from selected endpoint nodes.
    public var selectedEdges: [DocumentEdge] { edges.filter { selectedEdgeIDs.contains($0.id) } }
    /// Unique nodes used by ordinary transforms: explicit nodes plus both endpoints of every explicit edge.
    public var transformNodeIDs: Set<String> {
        selectedEdges.reduce(into: selectedIDs) { $0.formUnion([$1.fromID, $1.toID]) }
    }
    /// Transform participants in document order, retaining read-only rows for inspection.
    public var transformNodes: [DocumentNode] {
        let ids = transformNodeIDs
        return nodes.filter { ids.contains($0.id) }
    }
    /// Additive radius input acts on editable transform participants unless the radius constraint is locked.
    public var canAdjustSelectionRadius: Bool {
        !locks.contains(.radius) && transformNodes.contains(where: \.isEditable)
    }

    /// Hovered radius input never changes selection and is available only while every selection context is empty.
    /// - Parameter id: Exact hovered node identity in the originating canvas.
    /// - Returns: Whether that node is editable and radius input is unlocked.
    public func canAdjustNodeRadius(id: String) -> Bool {
        selectedIDs.isEmpty && selectedEdgeIDs.isEmpty && selectedPartID == nil && selectedComponentIDs.isEmpty
            && !locks.contains(.radius) && nodes.contains { $0.id == id && $0.isEditable }
    }

    /// All explicit edges must have editable endpoints before a batch edge command can run.
    public var canEditSelectedEdges: Bool {
        !selectedEdgeIDs.isEmpty && selectedEdgeIDs.isSubset(of: Set(editableEdges.map(\.id)))
    }
    /// Combined delete consumes explicit picks; read-only nodes are skipped, read-only edges reject the batch.
    public var canDeleteSelection: Bool {
        (selectedEdgeIDs.isEmpty || canEditSelectedEdges)
            && (!selectedEdgeIDs.isEmpty || selectedNodes.contains(where: \.isEditable))
    }
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
    public var selectedPart: DocumentPart? {
        guard let selectedPartID else { return nil }
        return parts.first { $0.id.utf8.elementsEqual(selectedPartID.utf8) }
    }

    /// The part shown in the Part inspector, respecting singleton component inspector precedence.
    package var inspectedPart: DocumentPart? {
        guard selectedComponent == nil else { return nil }
        return selectedPart ?? selectedLinkedComponentPart
    }

    /// The sole part linked directly by the selected component rows, counting shared links once.
    public var selectedLinkedComponentPart: DocumentPart? {
        let owners = Set(selectedComponentRows.compactMap { $0.component.partID.map { Data($0.utf8) } })
        guard owners.count == 1, let owner = owners.first else { return nil }
        return parts.first { Data($0.id.utf8) == owner }
    }
    /// Explanation for a loaded document whose preview currently has no geometry.
    /// - Returns: A next-step description for an empty graph, excluded contributors or successful empty generation.
    /// - Example: `snapshot.previewEmptyDescription` supplies the empty preview's message.
    public var previewEmptyDescription: String {
        if nodes.isEmpty { return "Add nodes to begin modeling." }
        if !hasEnabledGeometry { return "Enable a model or stitching part to generate the mesh." }
        return "The current document generates no mesh geometry."
    }

    /// Visibility is an editing option. Disabled parts and cross-section-only profiles do not contribute joined geometry.
    public var hasEnabledGeometry: Bool {
        let excluded = Set(parts.filter { $0.isDisabled || $0.target == .cutFace }.map(\.id))
        return nodes.contains { node in node.partID.map { !excluded.contains($0) } ?? true }
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
            && (selectedEdgeIDs.isEmpty || canEditSelectedEdges)
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
        guard selectedComponentIDs.isEmpty, selectedPartID == nil, selectedEdgeIDs.isEmpty, selectedIDs.count <= 1
        else {
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
    private var componentRevealHint: ComponentRevealHint?
    private var componentRevealRevision = 0
    private var selectedID: String?
    private var selectedIDs: Set<String> = []
    private var selectedEdgeIDs: Set<String> = []
    private var selectedPartID: String?
    private var locks: Set<EditingConstraint> = []
    private var revision = 0
    private var constraintRevision = 0
    private var selectionRevision = 0

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
            componentTree: componentTree, rigSettings: contents.rigSettings,
            colorImageAssets: history.document.colorImageAssets(),
            selectedComponentIDs: selectedComponentIDs, componentRevealHint: componentRevealHint,
            origin: contents.origin,
            selectedID: selectedID, selectedIDs: selectedIDs, selectedEdgeIDs: selectedEdgeIDs,
            canInsertSelectedEdgeMidpoints: !selectedEdgeIDs.isEmpty
                && history.document.canInsertEdgeMidpoints(ids: Array(selectedEdgeIDs)),
            canReduceSelectedNodes: !selectedIDs.isEmpty && history.document.canReduceNodes(Array(selectedIDs)),
            selectedPartID: selectedPartID,
            canUndo: history.canUndo, canRedo: history.canRedo,
            locks: locks,
            documentRevision: revision, previewIdentity: history.previewIdentity,
            constraintRevision: constraintRevision,
            selectionRevision: selectionRevision
        )
    }

    /// Select a single node or clear the transient selection.
    public mutating func select(_ id: String?) throws {
        try select(id.map { Set([$0]) } ?? [])
    }

    /// Replace explicit nodes while clearing edges, parts and components. Invalid identities reject atomically.
    public mutating func select(_ ids: Set<String>) throws { try selectGraph(nodes: ids, edges: []) }

    /// Replace both explicit graph sets atomically; invalid nodes/edges never change the prior selection.
    /// - Parameters: `nodes` and `edges` are independent existing identities; endpoint nodes are never inferred.
    /// - Throws: `missingNode` or `invalidNode`. Example: `try state.selectGraph(nodes: ["a"], edges: ["edge"])`.
    public mutating func selectGraph(nodes: Set<String>, edges: Set<String>) throws {
        let existing = Set(contents.nodes.map(\.id))
        if let missing = nodes.subtracting(existing).sorted().first { throw DocumentError.missingNode(missing) }
        guard edges.isSubset(of: Set(contents.edges.map(\.id))) else { throw DocumentError.invalidNode }
        componentRevealHint = nil
        let nodesChanged = Set(nodes.map { Data($0.utf8) }) != Set(selectedIDs.map { Data($0.utf8) })
        let edgesChanged = Set(edges.map { Data($0.utf8) }) != Set(selectedEdgeIDs.map { Data($0.utf8) })
        if nodesChanged || edgesChanged || selectedPartID != nil || !selectedComponentIDs.isEmpty {
            selectionRevision += 1
        }
        selectedIDs = nodes
        selectedID = contents.nodes.first { nodes.contains($0.id) }?.id
        selectedEdgeIDs = edges
        selectedPartID = nil
        selectedComponentIDs = []
    }

    /// Select every explicitly owned node and edge of a targeted part, including disconnected and read-only objects.
    /// - Parameters: `target` resolves actual stored ownership; `context` optionally rejects queued stale-document actions.
    /// - Throws: Missing/owner errors or `stalePartGraphSelection` atomically; no archive/history/preview changes occur.
    /// - Note: Repeat graph selection is a selection-epoch no-op, but publishes a fresh independent reveal hint.
    public mutating func selectWholePart(_ target: PartGraphTarget, context: PartGraphSelectionContext? = nil) throws {
        if let context, !context.isCurrent(in: snapshot) { throw EditorError.stalePartGraphSelection }
        let partID = try snapshot.resolvedPartGraphID(for: target)
        let nodes = Set(contents.nodes.filter { $0.partID == partID }.map(\.id))
        let edges = Set(contents.edges.filter { $0.partID == partID }.map(\.id))
        try selectGraph(nodes: nodes, edges: edges)
        componentRevealRevision += 1
        componentRevealHint = ComponentRevealHint.make(
            partID: partID, tree: componentTree, revision: componentRevealRevision)
    }

    package mutating func revealOwningComponent(
        _ target: PartGraphTarget, context: PartGraphSelectionContext
    ) throws {
        let current = snapshot
        guard context.isCurrent(in: current) else { throw EditorError.stalePartGraphSelection }
        guard let id = current.owningComponentID(for: target),
            let hint = ComponentRevealHint.make(
                componentID: id, tree: componentTree, revision: componentRevealRevision + 1)
        else { throw DocumentError.invalidComponent }
        componentRevealRevision = hint.revision
        componentRevealHint = hint
    }

    /// Select only a targeted part's owned nodes, preserving the separate node-only convenience.
    /// - Parameters: `partID` is an existing part; `context` captures the originating document epoch.
    /// - Throws: Missing-part or `stalePartGraphSelection` errors atomically. Edges and reveal hints are cleared.
    public mutating func selectPartNodes(_ partID: String, context: PartGraphSelectionContext? = nil) throws {
        if let context, !context.isCurrent(in: snapshot) { throw EditorError.stalePartGraphSelection }
        let resolved = try snapshot.resolvedPartGraphID(for: .part(partID))
        try select(Set(contents.nodes.filter { $0.partID == resolved }.map(\.id)))
    }

    /// Add graph objects from the captured component subtrees without editing the document.
    public mutating func selectComponentGraph(_ target: ComponentGraphSelectionTarget) throws {
        guard let graph = snapshot.componentGraph(target) else { throw EditorError.stalePartGraphSelection }
        guard !graph.nodes.isEmpty || !graph.edges.isEmpty else { return }
        try addToSelection(nodes: graph.nodes, edges: graph.edges)
    }

    /// Add independent graph identities in one selection epoch; validation matches `selectGraph(nodes:edges:)`.
    public mutating func addToSelection(nodes: Set<String>, edges: Set<String>) throws {
        try selectGraph(nodes: selectedIDs.union(nodes), edges: selectedEdgeIDs.union(edges))
    }

    /// Remove existing explicit graph identities without adding unselected hits or inferring endpoints.
    /// - Parameters: `nodes` and `edges` are independently validated exact UTF-8 source identities.
    /// - Throws: `missingNode` or `invalidNode` before any selection changes for an unknown identity.
    /// - Note: An empty or unselected hit set preserves selection epochs, inspector and reveal intent.
    /// - Example: `try state.removeFromSelection(nodes: ["a"], edges: ["edge"])`.
    public mutating func removeFromSelection(nodes: Set<String>, edges: Set<String>) throws {
        let existingNodes = Set(contents.nodes.map { Data($0.id.utf8) })
        if let missing = nodes.filter({ !existingNodes.contains(Data($0.utf8)) }).sorted().first {
            throw DocumentError.missingNode(missing)
        }
        let nodeKeys = Set(nodes.map { Data($0.utf8) })
        let edgeKeys = Set(edges.map { Data($0.utf8) })
        guard edgeKeys.isSubset(of: Set(contents.edges.map { Data($0.id.utf8) })) else {
            throw DocumentError.invalidNode
        }
        let remainingNodes = selectedIDs.filter { !nodeKeys.contains(Data($0.utf8)) }
        let remainingEdges = selectedEdgeIDs.filter { !edgeKeys.contains(Data($0.utf8)) }
        guard remainingNodes.count != selectedIDs.count || remainingEdges.count != selectedEdgeIDs.count else { return }
        try selectGraph(nodes: remainingNodes, edges: remainingEdges)
    }

    /// Toggle each independent graph identity once, preserving the other picks; invalid identities reject atomically.
    public mutating func toggleGraphSelection(nodes: Set<String>, edges: Set<String>) throws {
        guard nodes.isSubset(of: Set(contents.nodes.map(\.id))), edges.isSubset(of: Set(contents.edges.map(\.id)))
        else {
            throw DocumentError.invalidNode
        }
        try selectGraph(
            nodes: selectedIDs.symmetricDifference(nodes), edges: selectedEdgeIDs.symmetricDifference(edges))
    }

    /// Replace selection with explicit edges; nodes, parts and components are cleared.
    public mutating func selectEdges(_ ids: Set<String>) throws { try selectGraph(nodes: [], edges: ids) }

    /// Inspect an existing edge or clear the full graph selection; invalid identities reject atomically.
    public mutating func selectEdge(_ id: String?) throws { try selectEdges(id.map { Set([$0]) } ?? []) }

    /// Toggle one explicit edge while retaining explicit nodes and other edges.
    public mutating func toggleEdgeSelection(_ id: String) throws { try toggleGraphSelection(nodes: [], edges: [id]) }

    /// Inspect an existing part or clear selection. Missing IDs throw DocumentError.missingPart atomically.
    public mutating func selectPart(_ id: String?) throws {
        if let id, !contents.parts.contains(where: { $0.id.utf8.elementsEqual(id.utf8) }) {
            throw DocumentError.missingPart(id)
        }
        componentRevealHint = nil
        let partChanged = id.map { Data($0.utf8) } != selectedPartID.map { Data($0.utf8) }
        if partChanged || !selectedEdgeIDs.isEmpty || !selectedComponentIDs.isEmpty || !selectedIDs.isEmpty {
            selectionRevision += 1
        }
        selectedPartID = id
        selectedComponentIDs = []
        selectedEdgeIDs = []
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
        componentRevealHint = nil
        let exactIDs = Set(ids.map { Data($0.utf8) })
        let previousExactIDs = Set(selectedComponentIDs.map { Data($0.utf8) })
        if exactIDs != previousExactIDs || selectedPartID != nil || !selectedEdgeIDs.isEmpty || !selectedIDs.isEmpty {
            selectionRevision += 1
        }
        selectedComponentIDs = ids
        selectedPartID = nil
        selectedEdgeIDs = []
        selectedID = nil
        selectedIDs = []
    }

    /// Apply one preflighted bulk role command, then reveal its reused or newly created stitching group.
    /// Selection/reveal alone remains history-free when all source roles already match.
    public mutating func setSelectedComponentPartRole(
        _ role: PartTarget, target: ComponentPartRoleTarget, newGroupID: String?
    ) throws {
        guard target.isCurrent(in: snapshot) else { throw ComponentPartRoleError.staleContext }
        let plan = try snapshot.componentPartRolePlan(role)
        var next = self
        try next.apply([.setComponentPartRoles(componentIDs: plan.componentIDs, target: role, newGroupID: newGroupID)])
        if let group = plan.requiresNewGroup ? newGroupID : plan.revealGroupID {
            try next.selectComponent(group)
            next.componentRevealRevision += 1
            next.componentRevealHint = ComponentRevealHint.make(
                componentID: group, tree: next.componentTree, revision: next.componentRevealRevision)
        }
        try Task.checkCancellation()
        self = next
    }

    /// Apply image commands only to the captured current document/revision/component.
    /// - Parameters: command is the image mutation; target captures the intended singleton selection.
    /// - Throws: `staleColorImageTarget` or original document/resource errors atomically.
    mutating func applyColorImage(_ command: DocumentCommand, target: ComponentColorImageTarget) throws {
        guard target.isCurrent(in: snapshot) else { throw EditorError.staleColorImageTarget }
        try apply([command])
    }

    /// Move the captured selected subtree to an explicit parent in one undo step.
    /// - Parameters:
    ///   - parent: Root or a supported group identity, revalidated by the document command.
    ///   - target: Window/document epoch and selected component captured before choosing a destination.
    /// - Throws: `EditorError.staleComponentMove` or typed hierarchy/limit errors without partial publication.
    public mutating func reparentComponent(to parent: ComponentParent, target: ComponentReparentTarget) throws {
        guard target.isCurrent(in: snapshot) else { throw EditorError.staleComponentMove }
        try apply([.reparentComponent(id: target.componentID, parentID: parent.componentID)])
    }

    /// Toggle a node without modifying document data or history.
    public mutating func toggleSelection(_ id: String) throws {
        try toggleGraphSelection(nodes: [id], edges: [])
    }

    /// Include every explicit graph object, including read-only objects for inspection.
    public mutating func selectAll() {
        componentRevealHint = nil
        let nodes = Set(contents.nodes.map(\.id))
        let edges = Set(contents.edges.map(\.id))
        if selectedIDs != nodes || selectedEdgeIDs != edges || selectedPartID != nil || !selectedComponentIDs.isEmpty {
            selectionRevision += 1
        }
        selectedIDs = nodes
        selectedEdgeIDs = edges
        selectedID = contents.nodes.first?.id
        selectedPartID = nil
        selectedComponentIDs = []
    }

    /// Replace graph selection with every node only, retaining the explicit Select All Nodes convenience.
    public mutating func selectAllNodes() {
        componentRevealHint = nil
        let nodes = Set(contents.nodes.map(\.id))
        if selectedIDs != nodes || !selectedEdgeIDs.isEmpty || selectedPartID != nil || !selectedComponentIDs.isEmpty {
            selectionRevision += 1
        }
        selectedIDs = nodes
        selectedEdgeIDs = []
        selectedID = contents.nodes.first?.id
        selectedPartID = nil
        selectedComponentIDs = []
    }

    /// Commit one visible Add-mode click using supplied fresh identities. Creation bypasses interaction locks.
    /// - Parameters: `request` captures the visible ghost/epochs; `identities` supplies fresh graph identities.
    /// - Returns: Placement, connection or duplicate suppression, with any connection-fallback cause retained.
    /// - Throws: Stale, readonly, invalid geometry/identity/owner or quota errors atomically.
    public mutating func placeAddNode(_ request: AddPlacementRequest, identities: AddPlacementIdentities) throws
        -> (outcome: AddPlacementOutcome, connectionFallbackReason: String?)
    {
        guard request.target.isCurrent(in: snapshot) else { throw EditorError.staleAddPlacement }
        guard EditableNode(position: request.position, radius: request.radius).isValid,
            request.radius >= 0.001, request.radius <= 1
        else { throw EditorError.invalidAddPlacement }
        let anchor = request.anchorID.flatMap { id in contents.nodes.first { $0.id == id } }
        if let anchorID = request.anchorID {
            guard let anchor, anchor.id == anchorID, anchor.partID != nil else { throw DocumentError.invalidNode }
            guard anchor.isEditable else { throw EditorError.readOnlyNode }
            let degree = contents.edges.reduce(0) {
                $0 + ($1.fromID == anchorID ? 1 : 0) + ($1.toID == anchorID ? 1 : 0)
            }
            guard degree < 2 else { throw DocumentError.invalidNode }
        }
        guard componentTree.failureDescription == nil else { throw DocumentError.invalidComponentStructure }
        let fresh = [identities.nodeID, identities.partID, identities.componentID, identities.edgeID]
        func key(_ id: String) -> String {
            let bytes = Array(id.utf8)
            return bytes.count == 38 && bytes.first == 123 ? String(id.dropFirst().dropLast()) : id
        }
        let occupied = Set(
            (contents.nodes.map(\.id) + contents.edges.map(\.id) + contents.parts.map(\.id)
                + componentTree.rows.map(\.id)).map(key))
        guard
            fresh.allSatisfy({
                !$0.isEmpty && $0.utf8.count <= 128
                    && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            }),
            Set(fresh.map(key)).count == 4, occupied.isDisjoint(with: fresh.map(key))
        else { throw DocumentError.invalidNode }
        var fallbackReason: String?
        if let anchor, let candidateID = request.connectingTo,
            let candidate = contents.nodes.first(where: { $0.id == candidateID }), candidate.id != anchor.id,
            candidate.isEditable, candidate.partID != nil,
            contents.edges.reduce(0, { $0 + ($1.fromID == candidateID ? 1 : 0) + ($1.toID == candidateID ? 1 : 0) })
                < 2,
            !contents.edges.contains(where: {
                ($0.fromID == anchor.id && $0.toID == candidateID) || ($0.toID == anchor.id && $0.fromID == candidateID)
            })
        {
            guard contents.edges.count < 20_000 else { throw DocumentError.limitExceeded }
            var next = self
            do {
                try next.apply([.joinNodes(id: identities.edgeID, from: anchor.id, to: candidateID)])
                self = next
                return (.connected(edgeID: identities.edgeID), nil)
            } catch let error as DocumentError { fallbackReason = String(describing: error) }
        }
        if let last = request.lastAddedPosition,
            abs(last.x - request.position.x) <= 0.000001, abs(last.y - request.position.y) <= 0.000001,
            abs(last.z - request.position.z) <= 0.000001
        {
            return (.duplicate, fallbackReason)
        }
        guard contents.nodes.count < 10_000 else { throw DocumentError.limitExceeded }
        var commands: [DocumentCommand]
        if let anchor, let partID = anchor.partID {
            guard contents.edges.count < 20_000 else { throw DocumentError.limitExceeded }
            let reverse = try history.document.firstIncidentEdge(nodeID: anchor.id)?.fromID == anchor.id
            commands = [
                .addNode(
                    id: identities.nodeID, partID: partID, componentID: nil, position: request.position,
                    radius: request.radius),
                .addEdge(
                    id: identities.edgeID, from: reverse ? identities.nodeID : anchor.id,
                    to: reverse ? anchor.id : identities.nodeID),
            ]
        } else {
            guard contents.parts.count < 10_000, componentTree.rows.count < 10_000 else {
                throw DocumentError.limitExceeded
            }
            commands = [
                .addNode(
                    id: identities.nodeID, partID: identities.partID, componentID: identities.componentID,
                    position: request.position, radius: request.radius)
            ]
            if let parentID = request.parentID {
                commands.append(.reparentComponent(id: identities.componentID, parentID: parentID))
            }
        }
        try apply(commands, selecting: identities.nodeID)
        return (.placed(nodeID: identities.nodeID), fallbackReason)
    }

    /// Translate editable selected nodes as one atomic undo step. Read-only nodes stay fixed.
    public mutating func moveSelection(by delta: NodePosition, target: CanvasAdjustmentTarget? = nil) throws {
        if let target {
            guard target.isCurrent(in: snapshot) else { throw EditorError.staleCanvasAdjustment }
            try Task.checkCancellation()
            var next = self
            try next.moveSelection(by: delta)
            try Task.checkCancellation()
            self = next
            return
        }
        guard [delta.x, delta.y, delta.z].allSatisfy(\.isFinite) else { throw DocumentError.invalidNode }
        let updates = snapshot.transformNodes.filter(\.isEditable).map { node in
            let position = node.value.position
            return NodeUpdate(
                id: node.id,
                value: .init(
                    position: .init(x: position.x + delta.x, y: position.y + delta.y, z: position.z + delta.z),
                    radius: node.value.radius))
        }
        try apply([.setNodes(updates)])
    }

    /// Add one finite document-space radius delta to the selected node/edge-endpoint union, in one history step.
    /// - Parameters: `delta` is already divided by the actual canvas height; `target` optionally guards queued input.
    /// - Throws: `invalidNode` for nonfinite delta or `staleCanvasAdjustment` for a changed target.
    /// - Note: Nonzero edits clamp to 0.001...1. Zero, radius-locked and read-only edits retain source bytes.
    public mutating func adjustSelectionRadius(by delta: Double, target: CanvasAdjustmentTarget? = nil) throws {
        guard delta.isFinite else { throw DocumentError.invalidNode }
        if let target, !target.isCurrent(in: snapshot) { throw EditorError.staleCanvasAdjustment }
        try applyRadiusDelta(delta, nodes: snapshot.transformNodes)
    }

    /// Add a radius delta to one hovered node without selecting it, only while all transient selection is empty.
    /// - Parameters: `id` is the hovered node; `delta` is finite document-space input; `target` captures its window epoch.
    /// - Throws: `missingNode`, `invalidNode`, or `staleCanvasAdjustment`; read-only and radius-locked nodes are no-ops.
    public mutating func adjustNodeRadius(id: String, by delta: Double, target: CanvasAdjustmentTarget? = nil) throws {
        guard delta.isFinite else { throw DocumentError.invalidNode }
        if let target, !target.isCurrent(in: snapshot) { throw EditorError.staleCanvasAdjustment }
        guard selectedIDs.isEmpty, selectedEdgeIDs.isEmpty, selectedPartID == nil, selectedComponentIDs.isEmpty else {
            throw EditorError.staleCanvasAdjustment
        }
        guard let node = contents.nodes.first(where: { $0.id == id }) else { throw DocumentError.missingNode(id) }
        try applyRadiusDelta(delta, nodes: [node])
    }

    private mutating func applyRadiusDelta(_ delta: Double, nodes: [DocumentNode]) throws {
        guard delta != 0, !locks.contains(.radius) else { return }
        let updates = nodes.filter(\.isEditable).map { node in
            let radius: Double
            // Compare finite bounded differences before adding, so even extreme finite deltas saturate safely.
            if delta <= 0.001 - node.value.radius {
                radius = 0.001
            } else if delta >= 1 - node.value.radius {
                radius = 1
            } else {
                radius = node.value.radius + delta
            }
            return NodeUpdate(id: node.id, value: .init(position: node.value.position, radius: radius))
        }
        try apply([.setNodes(updates)])
    }

    /// Scale editable node positions about their centroid and radii independently.
    /// Factors must be finite and positive. Locks and read-only parts retain their values.
    public mutating func scaleSelection(
        positionFactor: Double, radiusFactor: Double, target: CanvasAdjustmentTarget? = nil
    ) throws {
        if let target, !target.isCurrent(in: snapshot) { throw EditorError.staleCanvasAdjustment }
        guard positionFactor.isFinite, radiusFactor.isFinite, positionFactor > 0, radiusFactor > 0 else {
            throw EditorError.invalidScale
        }
        let nodes = snapshot.transformNodes.filter(\.isEditable)
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
        let nodes = (transform == .exchangeXZ ? snapshot.selectedNodes : snapshot.transformNodes).filter(\.isEditable)
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

    /// Reverse only the captured explicit edge set in Qt UUID order, as one atomic history step.
    /// - Throws: Read-only or document validation errors; empty selection is a no-op.
    public mutating func reverseExplicitlySelectedEdges() throws {
        guard selectedEdgeIDs.isEmpty || snapshot.canEditSelectedEdges else { throw EditorError.readOnlyNode }
        try apply([.reverseEdges(GraphSelectionOrder.sorted(selectedEdgeIDs))])
    }

    /// Split every captured explicit edge with caller-supplied fresh identities, in Qt UUID order.
    /// - Parameter identities: Exactly one midpoint/new-edge identity tuple for each selected original edge.
    /// - Throws: Selection, identity, ownership, quota or read-only errors atomically. Original edges remain selected.
    public mutating func insertSelectedEdgeMidpoints(identities: [EdgeMidpointIdentity]) throws {
        guard identities.count == selectedEdgeIDs.count,
            Set(identities.map(\.originalEdgeID)) == selectedEdgeIDs
        else { throw DocumentError.invalidNode }
        guard selectedEdgeIDs.isEmpty || snapshot.canEditSelectedEdges else { throw EditorError.readOnlyNode }
        try apply([
            .insertEdgeMidpoints(
                identities.map {
                    EdgeMidpointInsertion(originalEdgeID: $0.originalEdgeID, nodeID: $0.nodeID, edgeID: $0.edgeID)
                })
        ])
    }

    /// Split the selected editable edge in one undo step, retaining its selection.
    /// - Parameters:
    ///   - nodeID: Fresh midpoint node identity.
    ///   - edgeID: Fresh identity for the second edge segment.
    /// - Throws: Invalid selection, read-only endpoint, or document validation errors atomically.
    public mutating func insertSelectedEdgeMidpoint(nodeID: String, edgeID: String) throws {
        guard let edge = snapshot.selectedEdge else { throw DocumentError.invalidNode }
        guard snapshot.canEditSelectedEdge else { throw EditorError.readOnlyNode }
        try apply([.insertEdgeMidpoint(id: edge.id, nodeID: nodeID, edgeID: edgeID)])
    }

    /// Reduce degree-two nodes in the full selection as one undo step.
    /// Degree-ineligible nodes remain selected; removed nodes are pruned from selection.
    /// - Throws: Document validation or read-only errors atomically.
    public mutating func reduceSelectedNodes() throws {
        try apply([.reduceNodes(Array(selectedIDs))])
    }

    /// Drag an anchor, retaining its group if selected; otherwise select only the anchor.
    public mutating func move(id: String, to position: NodePosition) throws {
        guard let node = contents.nodes.first(where: { $0.id == id }) else { throw DocumentError.missingNode(id) }
        guard node.isEditable else { throw EditorError.readOnlyNode }
        var next = self
        if !snapshot.transformNodeIDs.contains(id) { try next.select(id) }
        let original = node.value.position
        try next.moveSelection(
            by: .init(x: position.x - original.x, y: position.y - original.y, z: position.z - original.z))
        self = next
    }

    /// Low-level deletion without allocating identities. App callers use EditorSession.deleteSelection,
    /// which composes explicit split commands with removal in the same undo transaction.
    public mutating func deleteSelection() throws {
        try apply(selectionDeletionCommands())
    }

    /// Capture combined removals once; edges incident to removed nodes are removed by the node command.
    /// - Returns: Deduplicated explicit-edge removals followed by one explicit-node removal.
    /// - Throws: `readOnlyNode` when any explicitly selected edge is read-only; read-only nodes remain fixed.
    public func selectionDeletionCommands() throws -> [DocumentCommand] {
        guard selectedEdgeIDs.isEmpty || snapshot.canEditSelectedEdges else { throw EditorError.readOnlyNode }
        let removed = Set(snapshot.selectedNodes.filter(\.isEditable).map(\.id))
        let edges = snapshot.selectedEdges.filter { !removed.contains($0.fromID) && !removed.contains($0.toID) }
        let edgeIDs = Set(edges.map(\.id))
        var commands: [DocumentCommand] = edgeIDs.isEmpty ? [] : [.removeEdges(GraphSelectionOrder.sorted(edgeIDs))]
        if !removed.isEmpty { commands.append(.removeNodes(GraphSelectionOrder.sorted(removed))) }
        return commands
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
        try apply(commands, selecting: id, pasteParentID: nil)
    }

    mutating func apply(_ commands: [DocumentCommand], selecting id: String? = nil, pasteParentID: String?) throws {
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
            case .pasteNodes: try next.apply(command, pasteParentID: pasteParentID)
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
        guard !next.document.hasSameEditingState(as: history.document) else { return }
        let nextContents = try next.document.editorContents()
        let nextTree = ComponentTree(document: next.document)
        componentRevealHint = nil
        contents = nextContents
        componentTree = nextTree
        let previousNodes = selectedIDs
        let previousEdges = selectedEdgeIDs
        let previousComponents = selectedComponentIDs
        let previousPart = selectedPartID
        selectedComponentIDs.formIntersection(nextTree.rows.map(\.id))
        selectedIDs.formIntersection(contents.nodes.map(\.id))
        selectedEdgeIDs.formIntersection(contents.edges.map(\.id))
        selectedID = contents.nodes.first { selectedIDs.contains($0.id) }?.id
        if let selectedPartID, !contents.parts.contains(where: { $0.id.utf8.elementsEqual(selectedPartID.utf8) }) {
            self.selectedPartID = nil
        }
        if previousNodes != selectedIDs || previousEdges != selectedEdgeIDs
            || previousComponents != selectedComponentIDs
            || previousPart != selectedPartID
        {
            selectionRevision += 1
        }
        history = next
        revision += 1
    }
}
