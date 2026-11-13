import Dust3DDocument
import Foundation

/// Explicit transient graph selection intent. Native input maps its own modifiers to these operations.
package enum GraphSelectionMode: Sendable {
    case replace, add, toggle, subtract
}

/// Serializes XML parsing and commands away from the UI actor. A window owns one session.
public actor EditorSession {
    private var state: EditorState?
    private var hasAcceptedSource = false
    private var selectedAnimationID: String?
    private var lastPasteIdentifier: String?
    private var pasteOrdinal = 0
    private var lastQtTransfer: (snapshot: Data, identifier: String)?

    public init() {}

    public func open(data: Data) throws -> EditorSnapshot {
        try Task.checkCancellation()
        hasAcceptedSource = false
        let next = try EditorState(document: Dust3DDocument(data: data))
        try Task.checkCancellation()
        state = next
        hasAcceptedSource = true
        selectedAnimationID = nil
        lastPasteIdentifier = nil
        pasteOrdinal = 0
        lastQtTransfer = nil
        return next.snapshot
    }

    /// Query optional stored-intent presentation off-main without coupling it to graph snapshots.
    /// - Returns: One source-correlated editor/list value; an uninterpretable catalog retains its cause.
    /// - Throws: Cancellation or `notLoaded`; optional metadata errors never block primary editing.
    /// - Example: `let list = try await session.animationSnapshot()`.
    public func animationSnapshot() throws -> EditorAnimationSnapshot {
        try Task.checkCancellation()
        guard let state else { throw EditorError.notLoaded }
        let result = Self.animationSnapshot(state, selectedID: selectedAnimationID)
        try Task.checkCancellation()
        selectedAnimationID = result.list.selectedRow?.source.id
        return result
    }

    /// Select stored intent independently of graph selection, document bytes, revision and history.
    /// - Parameter id: Exact source spelling or nil to clear, including when metadata is unavailable.
    /// - Returns: Current source-correlated presentation.
    /// - Throws: Original catalog cause or `missingAnimation`, cancellation or `notLoaded`, atomically.
    /// - Example: `try await session.selectAnimation(id)`.
    public func selectAnimation(_ id: String?) throws -> EditorAnimationSnapshot {
        try Task.checkCancellation()
        guard let state else { throw EditorError.notLoaded }
        let result = Self.animationSnapshot(state, selectedID: id)
        try Task.checkCancellation()
        if let id {
            if let cause = result.list.issue { throw cause }
            guard result.list.selectedRow != nil else { throw DocumentAnimationError.missingAnimation(id) }
        }
        selectedAnimationID = result.list.selectedRow?.source.id
        return result
    }

    /// Create/select one stored record using a fresh UUID, without native evaluation.
    /// - Parameters: name/type follow the document's bounded text rules; unknown types remain stored intent.
    /// - Returns: Committed source/history plus optional presentation; no post-commit cancellation check.
    /// - Throws: Original document/load/cancellation errors before publication.
    /// - Example: `try await session.createAnimation(name: "Walk", type: "walk")`.
    public func createAnimation(name: String, type: String) throws -> EditorAnimationSnapshot {
        try insertAnimation { .createAnimation(id: $0, name: name, type: type) }
    }

    /// Create stored intent only while the draft's captured document remains current.
    /// - Parameters: name/type are bounded stored text; parameters are ordered initial values;
    ///   target identifies the source before drafting. All fields commit as one undo transaction.
    /// - Returns: Committed source/history selecting a fresh record.
    /// - Throws: `staleAnimationTarget`, cancellation, not-loaded or original document cause.
    ///   Source validation precedes identifier allocation and any document mutation.
    /// - Example: `try await session.createAnimation(name: "Idle", type: "BipedIdle", target: target)`.
    public func createAnimation(
        name: String, type: String, parameters: [DocumentAnimationParameter] = [], target: AnimationCreationTarget
    ) throws -> EditorAnimationSnapshot {
        try Task.checkCancellation()
        guard let state else { throw EditorError.notLoaded }
        guard target.isCurrent(in: state.snapshot) else { throw EditorError.staleAnimationTarget }
        return try insertAnimationCommands({ id in
            [.createAnimation(id: id, name: name, type: type)]
                + parameters.map { .setAnimationParameter(id: id, name: $0.name, value: $0.value) }
        })
    }

    /// Duplicate/select complete stored intent using a fresh UUID; opaque data remains preserved.
    /// - Parameters: id identifies the source record exactly; name is the new bounded display name.
    /// - Returns: Committed source/history plus optional presentation.
    /// - Throws: Original document/load/cancellation errors atomically; no clip is evaluated.
    /// - Example: `try await session.duplicateAnimation(id: id, name: "Walk copy")`.
    public func duplicateAnimation(id: String, name: String) throws -> EditorAnimationSnapshot {
        try insertAnimation { .duplicateAnimation(id: id, newID: $0, name: name) }
    }

    /// Apply an edit only to its captured source row and semantic epoch.
    /// - Parameters: edit selects the bounded document command; target captures row/document identity.
    /// - Returns: One committed editor/list snapshot with existing transient selection normalized.
    /// - Throws: `staleAnimationTarget` or original document/load/cancellation cause, atomically.
    /// - Example: `try await session.editAnimation(.rename("Rest"), target: target)`.
    public func editAnimation(_ edit: AnimationEdit, target: AnimationEditTarget) throws -> EditorAnimationSnapshot {
        try editAnimation([edit], target: target)
    }

    /// Commit one captured parameter/type draft as a single undo transaction.
    /// - Parameters: edits are ordered stored-intent changes; target binds every change to one source row.
    /// - Returns: One committed editor/list observation; empty and net-zero drafts retain Redo.
    /// - Throws: Stale-target or original document/load/cancellation cause, with no partial publication.
    /// - Example: `try await session.editAnimation([.setType("BipedIdle"), .setParameter(name: "frameCount", value: "30")], target: target)`.
    public func editAnimation(_ edits: [AnimationEdit], target: AnimationEditTarget) throws -> EditorAnimationSnapshot {
        var next = try validatedAnimationState(for: target)
        try next.apply(edits.map { $0.command(id: target.animationID) })
        let result = Self.animationSnapshot(next, selectedID: selectedAnimationID)
        try Task.checkCancellation()
        state = next
        selectedAnimationID = result.list.selectedRow?.source.id
        return result
    }

    /// Duplicate a captured row only while its source epoch remains current.
    /// - Parameters: target captures the exact source; name is the bounded new display name.
    /// - Returns: One committed editor/list snapshot selecting a fresh UUID record.
    /// - Throws: Stale-target or original document/load/cancellation errors before publication.
    /// - Example: `try await session.duplicateAnimation(target: target, name: "Rest copy")`.
    public func duplicateAnimation(target: AnimationEditTarget, name: String) throws -> EditorAnimationSnapshot {
        _ = try validatedAnimationState(for: target)
        return try duplicateAnimation(id: target.animationID, name: name)
    }

    private func validatedAnimationState(for target: AnimationEditTarget) throws -> EditorState {
        try Task.checkCancellation()
        guard let state else { throw EditorError.notLoaded }
        guard target.isCurrent(in: state.snapshot) else { throw EditorError.staleAnimationTarget }
        return state
    }

    private func insertAnimation(_ command: (String) -> DocumentCommand) throws -> EditorAnimationSnapshot {
        try insertAnimationCommands({ [command($0)] })
    }

    private func insertAnimationCommands(_ commands: (String) -> [DocumentCommand]) throws -> EditorAnimationSnapshot {
        try Task.checkCancellation()
        guard var next = state else { throw EditorError.notLoaded }
        let id = Self.identifier()
        try next.apply(commands(id))
        let result = Self.animationSnapshot(next, selectedID: id)
        try Task.checkCancellation()
        state = next
        selectedAnimationID = result.list.selectedRow?.source.id
        return result
    }

    private static func animationSnapshot(_ state: EditorState, selectedID: String?) -> EditorAnimationSnapshot {
        let editor = state.snapshot
        let catalog = Result { try editor.document.animations() }
        return EditorAnimationSnapshot(
            editor: editor, list: AnimationListPresentation(catalog: catalog, selectedID: selectedID))
    }

    /// Admit export work only for the captured document identity and semantic revision.
    /// - Parameter target: Target captured before encoding; recheck before publication.
    /// - Throws: Cancellation, `notLoaded`, or `staleExport` without changing history/state.
    /// - Note: A successful check is not a lease; the app must serialize final publication with edits.
    /// - Example: `try await session.validateExport(target)`.
    public func validateExport(_ target: EditorExportTarget) throws {
        try Task.checkCancellation()
        guard let state else { throw EditorError.notLoaded }
        let snapshot = state.snapshot
        guard target.documentIdentity == snapshot.documentIdentity,
            target.documentRevision == snapshot.documentRevision
        else { throw EditorError.staleExport }
    }

    /// Validate and perform one synchronous final publication without admitting an intervening edit.
    /// - Parameters:
    ///   - target: Identity/revision captured with the archive supplied to the encoder.
    ///   - publication: Trusted synchronous source/destination checks and atomic write, performed once.
    /// - Throws: Cancellation or stale-target errors before the write, or its original filesystem error.
    /// - Note: This actor stays off-main. Encoding must finish before entering; the write temporarily
    ///   serializes accepted document commands. A committed write has no post-write cancellation check.
    /// - Example: `try await session.publishExport(target, publication: commit)`.
    public func publishExport(_ target: EditorExportTarget, publication: @Sendable () throws -> Void) throws {
        try validateExport(target)
        try publication()
    }

    /// Update this window's transient interaction lock state.
    public func setLock(_ constraint: EditingConstraint, isLocked: Bool) throws -> EditorSnapshot {
        try update { $0.setLock(constraint, isLocked: isLocked) }
    }

    package func toggleCanvasAxisLock(_ axis: EditingConstraint, target: CanvasAdjustmentTarget) throws
        -> EditorSnapshot
    {
        try update { state in
            let snapshot = state.snapshot
            guard hasAcceptedSource, target.isCurrent(in: snapshot), axis != .radius else {
                throw EditorError.staleCanvasAdjustment
            }
            state.setLock(axis, isLocked: !snapshot.locks.contains(axis))
        }
    }

    public func select(_ id: String?) throws -> EditorSnapshot { try update { try $0.select(id) } }

    public func select(_ ids: Set<String>) throws -> EditorSnapshot { try update { try $0.select(ids) } }
    /// Select one edge without dirtying the document or creating an undo entry.
    /// Atomically replace independent explicit node/edge sets; invalid identities preserve prior selection.
    public func selectGraph(nodes: Set<String>, edges: Set<String>) throws -> EditorSnapshot {
        try update { try $0.selectGraph(nodes: nodes, edges: edges) }
    }
    package func applyGraphPicks(
        nodes: Set<String>, edges: Set<String>, mode: GraphSelectionMode, target: CanvasAdjustmentTarget? = nil
    ) throws -> EditorSnapshot {
        try update { state in
            if let target, !hasAcceptedSource || !target.isCurrent(in: state.snapshot) {
                throw EditorError.staleCanvasAdjustment
            }
            switch mode {
            case .replace: try state.selectGraph(nodes: nodes, edges: edges)
            case .add: try state.addToSelection(nodes: nodes, edges: edges)
            case .toggle: try state.toggleGraphSelection(nodes: nodes, edges: edges)
            case .subtract: try state.removeFromSelection(nodes: nodes, edges: edges)
            }
        }
    }

    package func applyLasso(
        plan: CanvasLassoPickPlan, path: CanvasLasso, target: CanvasAdjustmentTarget
    ) throws -> EditorSnapshot {
        try Task.checkCancellation()
        let hits = plan.hits(in: path)
        try Task.checkCancellation()
        return try applyGraphPicks(nodes: hits.nodes, edges: hits.edges, mode: plan.mode, target: target)
    }

    /// Select a target part's complete owned graph and request an independent owning-component reveal.
    /// - Parameters: `target` is a part/node/edge; `context` captures the originating document epoch.
    /// - Returns: Unchanged archive/history with atomic explicit graph selection and reveal metadata.
    /// - Throws: Missing, invalid-owner or stale-target errors without changing selection.
    public func selectWholePart(_ target: PartGraphTarget, context: PartGraphSelectionContext? = nil) throws
        -> EditorSnapshot
    {
        try update { try $0.selectWholePart(target, context: context) }
    }
    package func revealOwningComponent(
        _ target: PartGraphTarget, context: PartGraphSelectionContext, selecting: Bool = false
    ) throws -> EditorSnapshot {
        try update { try $0.revealOwningComponent(target, context: context, selecting: selecting) }
    }

    /// Select only the captured existing part's nodes without edge inference, history or reveal side effects.
    /// - Throws: Missing-part or stale-document errors without changing the current selection.
    public func selectPartNodes(_ partID: String, context: PartGraphSelectionContext? = nil) throws -> EditorSnapshot {
        try update { try $0.selectPartNodes(partID, context: context) }
    }
    /// Select visible, unlocked graph objects in the captured component subtrees.
    public func selectComponentGraph(_ target: ComponentGraphSelectionTarget) throws -> EditorSnapshot {
        try update { try $0.selectComponentGraph(target) }
    }

    /// Add graph picks atomically while preserving existing explicit nodes/edges.
    public func addToSelection(nodes: Set<String>, edges: Set<String>) throws -> EditorSnapshot {
        try update { try $0.addToSelection(nodes: nodes, edges: edges) }
    }
    /// Remove independent explicit graph picks in one transient selection epoch, retaining source and history.
    /// - Parameters: `nodes` and `edges` must be existing exact UTF-8 source identities, even when unselected.
    /// - Returns: Updated graph selection; no-hit removals preserve inspector and reveal intent.
    /// - Throws: `missingNode` or `invalidNode` without partial selection changes.
    public func removeFromSelection(nodes: Set<String>, edges: Set<String>) throws -> EditorSnapshot {
        try update { try $0.removeFromSelection(nodes: nodes, edges: edges) }
    }
    /// Toggle each supplied graph pick once in one selection epoch.
    public func toggleGraphSelection(nodes: Set<String>, edges: Set<String>) throws -> EditorSnapshot {
        try update { try $0.toggleGraphSelection(nodes: nodes, edges: edges) }
    }
    /// Replace selection with an explicit edge set, clearing node/component/part selection.
    public func selectEdges(_ ids: Set<String>) throws -> EditorSnapshot { try update { try $0.selectEdges(ids) } }

    package func selectEdges(_ ids: Set<String>, target: CanvasAdjustmentTarget) throws -> EditorSnapshot {
        try update { state in
            guard hasAcceptedSource, target.isCurrent(in: state.snapshot) else {
                throw EditorError.staleCanvasAdjustment
            }
            try state.selectEdges(ids)
        }
    }
    /// Toggle one explicit edge while preserving the other graph selections.
    public func toggleEdgeSelection(_ id: String) throws -> EditorSnapshot {
        try update { try $0.toggleEdgeSelection(id) }
    }
    public func selectEdge(_ id: String?) throws -> EditorSnapshot { try update { try $0.selectEdge(id) } }
    /// Inspect a part without changing document bytes or undo history.
    /// Wrap explicit sibling identities in a fresh group and inspect that group in one atomic publication.
    /// - Parameter ids: Nonempty sibling identities; source order is retained independent of Set iteration.
    /// - Returns: One undoable snapshot with a fresh UUID component selected.
    /// - Throws: Load/cancellation, hierarchy, identity or bounded-archive errors without partial state.
    public func groupComponents(_ ids: Set<String>) throws -> EditorSnapshot {
        try groupComponents(ids, target: nil)
    }

    package func groupComponents(_ ids: Set<String>, target: CanvasAdjustmentTarget?) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: target != nil) { state in
            if let target, !hasAcceptedSource || !target.isCurrent(in: state.snapshot) {
                throw ComponentGroupingError.staleTarget
            }
            let groupID = Self.identifier()
            try state.apply([.groupComponents(ids: ids.sorted(), groupID: groupID)])
            try state.selectComponent(groupID)
        }.snapshot
    }

    /// Atomically replace one mesh setting on the captured component selection.
    /// - Returns: The unchanged snapshot for semantic no-ops, or one undoable publication.
    public func editSelectedComponentMeshSettings(
        _ edit: ComponentMeshEdit, target: ComponentMeshSelectionTarget
    ) throws -> EditorSnapshot {
        try update { state in
            try state.editSelectedComponentMeshSettings(edit, target: target)
            try Task.checkCancellation()
        }
    }

    /// Apply color to the exact captured rows in one history step.
    public func editSelectedComponentColors(_ color: DocumentColor?, target: ComponentMeshSelectionTarget) throws
        -> EditorSnapshot
    {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard target.count > (target.isGraphSelection ? 0 : 1), target.isCurrent(in: state.snapshot) else {
                throw ComponentMeshSelectionError.staleTarget
            }
            let updates = target.ids.map { DocumentComponentColorUpdate(componentID: $0, color: color) }
            try state.apply([.setComponentColors(updates)])
        }.snapshot
    }

    /// Connect exactly two captured endpoints, allocating edge and legacy partition identities off the UI actor.
    /// - Throws: Stale intent, cancellation or the original joining error before atomic publication.
    public func connectSelectedNodes(target: NodeConnectionTarget, ownerID: String) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard hasAcceptedSource else { throw NodeConnectionSelectionError.staleTarget }
            try state.connectSelectedNodes(
                target: target, ownerID: ownerID, edgeID: "{\(UUID().uuidString.lowercased())}",
                splitIdentities: GraphCommandPreparation.splitIdentities)
        }.snapshot
    }

    /// Publish one atomic Ungroup for the exact originating row context, preserving graph/resources.
    public func ungroupComponents(target: ComponentUngroupTarget) throws -> EditorSnapshot {
        try update { state in
            try state.ungroupComponents(target: target)
            try Task.checkCancellation()
        }
    }

    /// Delete captured component subtrees atomically, retaining parts referenced by surviving instances.
    /// - Parameter target: The originating sidebar row/selection context and source epochs.
    /// - Returns: One undoable snapshot; removed selection is pruned and Undo does not resurrect selection.
    /// - Throws: Stale context, cancellation or original document validation errors before publication.
    /// - Example: `try await session.deleteComponentSubtrees(target: target)`.
    public func deleteComponentSubtrees(target: ComponentDeletionTarget) throws -> EditorSnapshot {
        try update { state in
            try state.deleteComponentSubtrees(target: target)
            try Task.checkCancellation()
        }
    }

    /// Apply one taper field to the original editable Model node without changing its position or radius.
    package func setNodeDeformationScale(
        _ property: PartDeformationProperty, value: Double, nodeID: String, target: CanvasAdjustmentTarget
    ) throws -> EditorSnapshot {
        try update { state in
            let snapshot = state.snapshot
            guard target.isCurrent(in: snapshot), snapshot.allowsNodeDeformation(for: nodeID) else {
                throw EditorError.staleCanvasAdjustment
            }
            try state.apply([.setNodeDeformationScale(id: nodeID, property: property, value: value)])
            try Task.checkCancellation()
        }
    }

    /// Restore just one saved deformation scale on the originally inspected Model part.
    package func resetPartDeformationScale(
        _ property: PartDeformationProperty, partID: String, target: CanvasAdjustmentTarget
    ) throws -> EditorSnapshot {
        try update { state in
            let snapshot = state.snapshot
            guard target.isCurrent(in: snapshot), let part = snapshot.inspectedPart, part.target == .model,
                part.id.utf8.elementsEqual(partID.utf8)
            else { throw EditorError.staleCanvasAdjustment }
            try state.apply([.setPartDeformationScale(id: partID, property: property, value: 1)])
            try Task.checkCancellation()
        }
    }

    /// Set an absolute cross-section rotation on the originally inspected Model part.
    package func setPartCutRotationPreset(
        _ preset: PartCutRotationPreset, partID: String, target: CanvasAdjustmentTarget
    ) throws -> EditorSnapshot {
        try update { state in
            let snapshot = state.snapshot
            guard target.isCurrent(in: snapshot), snapshot.allowsCutRotationPreset(for: partID)
            else { throw EditorError.staleCanvasAdjustment }
            try state.apply([.setPartCutRotation(id: partID, rotation: preset.halfTurns)])
            try Task.checkCancellation()
        }
    }

    package func editGraphPartCrossSection(
        _ edit: GraphPartCrossSectionEdit, target: GraphPartCrossSectionTarget
    ) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard hasAcceptedSource, target.isCurrent(in: state.snapshot), let part = target.part else {
                throw EditorError.staleCanvasAdjustment
            }
            let command: DocumentCommand
            switch edit {
            case .profile(let selection): command = .setPartCutFace(id: part.id, selection: selection)
            case .rotation(let value): command = .setPartCutRotation(id: part.id, rotation: value)
            case .deformationScale(let property, let value):
                command = .setPartDeformationScale(id: part.id, property: property, value: value)
            case .deformationUnified(let value): command = .setPartDeformationUnified(id: part.id, value: value)
            }
            try state.apply([command])
        }.snapshot
    }

    package func setGraphPartMaterial(
        _ property: PartMaterialProperty, value: Double, target: GraphModelPartTarget
    ) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard hasAcceptedSource, target.isCurrent(in: state.snapshot), let part = target.part else {
                throw EditorError.staleCanvasAdjustment
            }
            try state.apply([.setPartMaterial(id: part.id, property: property, value: value)])
        }.snapshot
    }

    /// Assign supported roles and perform any necessary stitching grouping in one undo/publication.
    /// Fresh group identities belong to this session, never the pure document planner.
    public func setSelectedComponentPartRole(_ role: PartTarget, target: ComponentPartRoleTarget) throws
        -> EditorSnapshot
    {
        try update { state in
            guard target.isCurrent(in: state.snapshot) else { throw ComponentPartRoleError.staleContext }
            let plan = try state.snapshot.componentPartRolePlan(role)
            try state.setSelectedComponentPartRole(
                role, target: target, newGroupID: plan.requiresNewGroup ? Self.identifier() : nil)
            try Task.checkCancellation()
        }
    }

    package func setGraphPartRole(_ role: PartTarget, target: GraphPartRoleTarget) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard hasAcceptedSource, target.isCurrent(in: state.snapshot), let part = target.part else {
                throw EditorError.staleCanvasAdjustment
            }
            try state.apply([.setPartTarget(id: part.id, target: role)])
        }.snapshot
    }

    /// Apply one equipment assignment to the captured Model component.
    package func setComponentEquipmentSlot(_ slot: String, target: ComponentEquipmentSlotTarget) throws
        -> EditorSnapshot
    {
        try update { state in
            guard hasAcceptedSource, target.isCurrent(in: state.snapshot) else {
                throw ComponentEquipmentSlotError.staleTarget
            }
            try state.apply([.setComponentEquipmentSlot(id: target.componentID, slot: slot)])
            try Task.checkCancellation()
        }
    }

    /// Apply one captured wrap-finish replacement away from the UI actor with one undo entry.
    /// - Parameters: edit is a typed field replacement; target belongs to the originating inspector.
    /// - Returns: The committed snapshot, preserving geometry identity for a finish-only edit.
    /// - Throws: Stale target, original document error or cancellation before publication.
    /// - Example: `try await session.editComponentSurface(.pattern(.spots), target: target)`.
    public func editComponentSurface(_ edit: ComponentSurfaceEdit, target: ComponentSurfaceTarget) throws
        -> EditorSnapshot
    {
        let result = try updateWithResult(checkCancellationBeforePublication: true) { state in
            try state.editComponentSurface(edit, target: target)
        }
        return result.snapshot
    }

    /// Apply one field to the captured group selection with one atomic history/publication step.
    public func editSelectedComponentWrapping(_ edit: ComponentWrappingEdit, target: ComponentWrappingSelectionTarget)
        throws -> EditorSnapshot
    {
        let result = try updateWithResult(checkCancellationBeforePublication: true) { state in
            try state.editSelectedComponentWrapping(edit, target: target)
        }
        return result.snapshot
    }

    /// Replace body-weight binding for the captured active wrapping group away from the UI actor.
    /// - Parameters: choice is an eligible group or Own Children; target captures source/selection/constraints.
    /// - Returns: One undoable snapshot with refreshed geometry/source-hint and material identities.
    /// - Throws: Cancellation, stale target or original document validation errors before publication.
    /// - Example: `try await session.editComponentWrapBinding(.group(bodyID), target: target)`.
    public func editComponentWrapBinding(
        _ choice: ComponentWrapBindingChoice, target: ComponentWrapBindingTarget
    ) throws -> EditorSnapshot {
        let result = try updateWithResult(checkCancellationBeforePublication: true) { state in
            try state.editComponentWrapBinding(choice, target: target)
        }
        return result.snapshot
    }

    /// Apply the captured mirror edit as one undoable publication, including any initial origin.
    public func setPartXMirrored(_ value: Bool, target: PartMirrorTarget) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard hasAcceptedSource, target.isCurrent(in: state.snapshot), let id = target.partID else {
                throw PartMirrorError.staleTarget
            }
            try state.apply([.setPartXMirrored(id: id, value: value)])
        }.snapshot
    }

    package func setGraphPartShape(
        _ property: PartModifierProperty, value: Bool, target: GraphPartShapeTarget
    ) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard GraphPartShapeTarget.properties.contains(property) else {
                throw GraphPartShapeError.unsupportedModifier
            }
            guard hasAcceptedSource, target.isCurrent(in: state.snapshot), let part = target.part else {
                throw GraphPartShapeError.staleTarget
            }
            try state.apply([.setPartModifier(id: part.id, property: property, value: value)])
        }.snapshot
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
    package func selectComponents(_ ids: Set<String>, target: CanvasAdjustmentTarget) throws -> EditorSnapshot {
        try update { state in
            guard target.isCurrent(in: state.snapshot) else { throw ComponentMeshSelectionError.staleTarget }
            try state.selectComponents(ids)
        }
    }

    /// Import validated PNG data and assign a fresh image identity to the captured component.
    /// - Parameters: png is platform-validated encoded data; target captures document/revision/selection.
    /// - Returns: One undoable snapshot with the component still selected.
    /// - Throws: Cancellation, stale-target or typed document/resource errors without partial state.
    public func importComponentColorImage(png: Data, target: ComponentColorImageTarget) throws -> EditorSnapshot {
        try update { state in
            try state.applyColorImage(
                .importComponentColorImage(id: target.componentID, imageID: Self.identifier(), png: png), target: target
            )
        }
    }

    /// Assign a retained image or clear an override after asynchronous validation.
    /// - Parameters: imageID is the retained identity or nil; target captures the intended component.
    /// - Returns: One undoable snapshot, or unchanged history for a semantic no-op.
    /// - Throws: Cancellation, stale-target or original reference errors atomically.
    public func setComponentColorImage(imageID: String?, target: ComponentColorImageTarget) throws -> EditorSnapshot {
        try update { state in
            try state.applyColorImage(.setComponentColorImage(id: target.componentID, imageID: imageID), target: target)
        }
    }

    package func importComponentColorImages(png: Data, target: ComponentMeshSelectionTarget) throws -> EditorSnapshot {
        try updateGraphColorImages(
            .importComponentColorImages(ids: target.ids, imageID: Self.identifier(), png: png), target: target)
    }

    package func setComponentColorImages(imageID: String?, target: ComponentMeshSelectionTarget) throws
        -> EditorSnapshot
    {
        try updateGraphColorImages(.setComponentColorImages(ids: target.ids, imageID: imageID), target: target)
    }

    private func updateGraphColorImages(_ command: DocumentCommand, target: ComponentMeshSelectionTarget) throws
        -> EditorSnapshot
    {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard !target.graphColorImageComponents(in: state.snapshot).isEmpty else {
                throw EditorError.staleColorImageTarget
            }
            try state.apply([command])
        }.snapshot
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
    /// Publish one atomic move of the captured component selection.
    public func reparentComponents(
        to parent: ComponentParent, target: ComponentBatchReparentTarget
    ) throws -> EditorSnapshot {
        try update { state in
            try state.reparentComponents(to: parent, target: target)
            try Task.checkCancellation()
        }
    }
    /// Validate and place the captured components in one undoable transaction.
    public func placeComponents(
        at placement: ComponentDropPlacement, target: ComponentPlacementTarget
    ) throws -> EditorSnapshot {
        try update { state in
            guard target.isCurrent(in: state.snapshot) else { throw EditorError.staleComponentMove }
            try state.apply([.placeComponents(ids: target.ids, placement: placement)])
            try Task.checkCancellation()
        }
    }
    public func placeComponents(
        in parent: ComponentParent, target: ComponentPlacementTarget
    ) throws -> EditorSnapshot {
        try placeComponents(at: .into(parentID: parent.componentID), target: target)
    }
    /// Apply the captured canvas isolation or restoration plan as one undo transaction.
    /// - Parameter target: Exact source, selection, constraint and component/part membership intent.
    /// - Returns: Current snapshot with unchanged geometry/material preview identities.
    /// - Throws: Cancellation, not-loaded, stale-target or original membership/document errors before publication.
    /// - Example: `try await session.setCanvasPartIsolation(target: target)`.
    public func setCanvasPartIsolation(target: CanvasPartIsolationTarget) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            let commands = try target.commands(in: state.snapshot)
            try state.apply(commands)
        }.snapshot
    }

    /// Change one flag on directly linked parts from the captured component selection.
    package func toggleCanvasPartState(
        _ property: PartStateProperty, target: CanvasPartStateTarget
    ) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard hasAcceptedSource, target.isCurrent(in: state.snapshot), property == .locked || property == .disabled
            else { throw EditorError.staleCanvasAdjustment }
            try state.apply([
                .setPartsState(ids: [target.part.id], property: property, value: !target.part.state(property))
            ])
        }.snapshot
    }

    public func setSelectedComponentPartState(
        _ property: PartStateProperty, value: Bool, target: ComponentMeshSelectionTarget
    ) throws -> EditorSnapshot {
        try update { state in
            let snapshot = state.snapshot
            guard target.isCurrent(in: snapshot) else { throw ComponentMeshSelectionError.staleTarget }
            let ids = snapshot.selectedComponentRows.compactMap { $0.component.partID }
            try state.apply([.setPartsState(ids: ids, property: property, value: value)])
            try Task.checkCancellation()
        }
    }

    /// Apply one thickness edit against the captured selected part and document/constraint revisions.
    /// - Returns: One atomic history entry, or unchanged history for a semantic no-op.
    /// - Throws: Cancellation, stale selection or document validation errors without partial publication.
    public func setPartHollowThickness(
        id: String, thickness: Double, target: CanvasAdjustmentTarget
    ) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            try Task.checkCancellation()
            guard target.isCurrent(in: state.snapshot), state.snapshot.selectedPart?.id == id else {
                throw EditorError.stalePartGraphSelection
            }
            try state.apply([.setPartHollowThickness(id: id, thickness: thickness)])
        }.snapshot
    }
    public func selectPart(_ id: String?) throws -> EditorSnapshot { try update { try $0.selectPart(id) } }
    public func toggleSelection(_ id: String) throws -> EditorSnapshot { try update { try $0.toggleSelection(id) } }
    public func selectAll() throws -> EditorSnapshot { try update { $0.selectAll() } }
    /// Replace selection with all explicit nodes and no explicit edges.
    public func selectAllNodes() throws -> EditorSnapshot { try update { $0.selectAllNodes() } }
    /// Explicitly center origin on all node radius bounds, honoring axis locks in one history transaction.
    /// - Returns: The committed snapshot, or unchanged history for an already-centered origin.
    /// - Throws: Load, cancellation, geometry or unavailable-origin errors without partial publication.
    public func centerOriginOnModel() throws -> EditorSnapshot {
        try update { try $0.centerOriginOnModel() }
    }
    public func moveSelection(by delta: NodePosition, target: CanvasAdjustmentTarget? = nil) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: target != nil) {
            try $0.moveSelection(by: delta, target: target)
        }.snapshot
    }
    /// Nudge a supported origin with the current native axis locks in one atomic history step.
    /// - Parameters: Converted finite delta and optional pre-await interaction target.
    /// - Returns: Current snapshot; a constrained no-op preserves redo/preview identity.
    /// - Throws: Load, cancellation, stale target, unavailable origin or bounded geometry errors.
    public func nudgeOrigin(by delta: NodePosition, target: CanvasAdjustmentTarget? = nil) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { try $0.nudgeOrigin(by: delta, target: target) }
            .snapshot
    }
    /// Apply a signed position-only centroid factor; zero/negative values match Qt's small-height spacing math.
    /// - Returns: One undoable snapshot, retaining selection and radii.
    /// - Throws: Load, cancellation, stale target, nonfinite factor or bounded geometry errors atomically.
    public func scaleSelectionPositions(factor: Double, target: CanvasAdjustmentTarget? = nil) throws -> EditorSnapshot
    {
        try updateWithResult(checkCancellationBeforePublication: true) {
            try $0.scaleSelectionPositions(factor: factor, target: target)
        }.snapshot
    }
    /// Scale the effective graph selection; an optional captured target rejects queued inputs from stale windows/epochs.
    public func scaleSelection(positionFactor: Double, radiusFactor: Double, target: CanvasAdjustmentTarget? = nil)
        throws -> EditorSnapshot
    {
        try update { try $0.scaleSelection(positionFactor: positionFactor, radiusFactor: radiusFactor, target: target) }
    }
    /// Apply an already-converted additive radius delta to the selected graph union as one undoable input activation.
    public func adjustSelectionRadius(by delta: Double, target: CanvasAdjustmentTarget? = nil) throws -> EditorSnapshot
    {
        try update { try $0.adjustSelectionRadius(by: delta, target: target) }
    }
    /// Adjust one captured hovered node without selecting it; every selection context must remain empty.
    public func adjustNodeRadius(id: String, by delta: Double, target: CanvasAdjustmentTarget? = nil) throws
        -> EditorSnapshot
    {
        try update { try $0.adjustNodeRadius(id: id, by: delta, target: target) }
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
        try update {
            guard hasAcceptedSource else { throw EditorError.staleReferenceComposition }
            try $0.applyReferenceComposition(png: png, origin: origin, target: target)
        }
    }

    /// Rotate connected descendants around the selected pivot without changing selection or radii.
    /// - Parameter rotation: Explicit Front/Side quarter-turn direction.
    /// - Returns: One undoable snapshot, or unchanged history for a no-op.
    /// - Throws: Load, cancellation, selection/origin/readonly or geometry validation errors atomically.
    public func rotateDescendants(_ rotation: DescendantRotation) throws -> EditorSnapshot {
        try update { try $0.rotateDescendants(rotation) }
    }
    /// Rotate the effective graph selection in the captured plane as one atomic history step.
    /// - Parameters: `degrees` is finite within signed 32-bit range; `target` rejects stale queued input.
    /// - Returns: The edited snapshot, or unchanged history for a no-op.
    /// - Throws: Load, cancellation, stale, angle, readonly or geometry errors.
    public func rotateSelection(degrees: Double, plane: EditingPlane, target: CanvasAdjustmentTarget? = nil) throws
        -> EditorSnapshot
    {
        try update { try $0.rotateSelection(degrees: degrees, plane: plane, target: target) }
    }
    package func rotateOrthogonalQuarterTurn(
        _ turn: OrthogonalQuarterTurn, from profile: EditingPlane, target: CanvasAdjustmentTarget
    ) throws -> EditorSnapshot {
        try update {
            guard hasAcceptedSource else { throw EditorError.staleCanvasAdjustment }
            try $0.rotateOrthogonalQuarterTurn(turn, from: profile, target: target)
        }
    }
    public func transformSelection(_ transform: SelectionTransform) throws -> EditorSnapshot {
        try update { try $0.transformSelection(transform) }
    }
    public func reverseSelectedEdges() throws -> EditorSnapshot {
        try update { try $0.reverseSelectedEdges() }
    }
    /// Validate captured contextual intent and reuse the existing atomic graph edit.
    /// No suspension separates source admission from delegated UUID/history work.
    /// - Parameter target: Frozen source, selection, constraints and initial availability.
    /// - Returns: The existing delegate's committed snapshot and complete history behavior.
    /// - Throws: Cancellation, notLoaded, stale/unavailable intent or the original edit error.
    public func performGraphSelectionAction(target: GraphSelectionActionTarget) throws -> EditorSnapshot {
        try Task.checkCancellation()
        guard let snapshot = state?.snapshot else { throw EditorError.notLoaded }
        guard target.isCurrent(in: snapshot) else { throw GraphSelectionActionError.staleTarget }
        guard target.isAvailable else { throw GraphSelectionActionError.unavailable }
        switch target.action {
        case .insertMidpoints: return try insertSelectedEdgeMidpoints()
        case .reverseEdges: return try reverseExplicitlySelectedEdges()
        case .reduceNodes: return try reduceSelectedNodes()
        case .deleteSelection: return try deleteSelection()
        }
    }

    /// Reverse captured explicit edges only, ordered by Qt UUID, in one history transaction.
    public func reverseExplicitlySelectedEdges() throws -> EditorSnapshot {
        try update { try $0.reverseExplicitlySelectedEdges() }
    }
    /// Split all explicit selected edges with fresh identities in one atomic history step.
    public func insertSelectedEdgeMidpoints() throws -> EditorSnapshot {
        try update { state in
            let identities = GraphSelectionOrder.sorted(state.snapshot.selectedEdgeIDs).map {
                EdgeMidpointIdentity(originalEdgeID: $0, nodeID: Self.identifier(), edgeID: Self.identifier())
            }
            try state.insertSelectedEdgeMidpoints(identities: identities)
        }
    }
    /// Insert a midpoint on the selected editable edge using fresh UUID identities.
    /// - Returns: One undoable snapshot retaining the original selected edge.
    /// - Throws: Load, cancellation, selection, editability or document validation errors atomically.
    public func insertSelectedEdgeMidpoint() throws -> EditorSnapshot {
        try update { try $0.insertSelectedEdgeMidpoint(nodeID: Self.identifier(), edgeID: Self.identifier()) }
    }
    /// Reduce the full node selection against the evolving graph in one history transaction.
    /// - Returns: Committed snapshot retaining only surviving selected nodes.
    /// - Throws: Load, cancellation or original document validation errors atomically.
    public func reduceSelectedNodes() throws -> EditorSnapshot {
        try update { try $0.reduceSelectedNodes() }
    }
    public func move(id: String, to position: NodePosition) throws -> EditorSnapshot {
        try update { try $0.move(id: id, to: position) }
    }
    /// Commit a canvas drag only while its captured document, selection and constraints remain current.
    /// - Parameters:
    ///   - drag: The immutable gesture baseline.
    ///   - translation: Total displacement in screen points.
    /// - Returns: The resulting snapshot as one undoable edit.
    /// - Throws: `EditorError.staleNodeDrag` or the original geometry and state error.
    public func commitNodeDrag(_ drag: NodeDrag, translation: CanvasPoint) throws -> EditorSnapshot {
        try update { state in
            guard drag.isCurrent(in: state.snapshot) else { throw EditorError.staleNodeDrag }
            guard translation.x.isFinite, translation.y.isFinite else { throw DocumentError.invalidNode }
            try state.move(id: drag.anchorID, to: drag.position(by: translation))
        }
    }

    /// Publish the captured Shift-drag result as one undoable graph edit.
    public func commitCanvasShiftDrag(_ drag: CanvasShiftDrag, translation: CanvasPoint) throws -> EditorSnapshot {
        try update { state in
            guard drag.isCurrent(in: state.snapshot) else { throw EditorError.staleNodeDrag }
            let updates = try drag.updates(by: translation)
            if !updates.isEmpty { try state.apply([.setNodes(updates)]) }
            try Task.checkCancellation()
        }
    }

    /// Bend a captured endpoint toward an explicit document-space position.
    public func bendEndpoint(_ target: EndpointIKTarget, toward destination: NodePosition) throws -> EditorSnapshot {
        try update { state in
            guard target.isCurrent(in: state.snapshot) else { throw EditorError.staleCanvasAdjustment }
            let updates = try target.updates(toward: destination)
            if !updates.isEmpty { try state.apply([.setNodes(updates)]) }
            try Task.checkCancellation()
        }
    }

    public func deleteSelection() throws -> EditorSnapshot {
        try update { state in
            let commands = try GraphCommandPreparation.normalizingDeletions(
                state.selectionDeletionCommands(), document: state.snapshot.document)
            try state.apply(commands)
        }
    }

    public func edit(id: String, position: NodePosition, radius: Double) throws -> EditorSnapshot {
        try update { try $0.edit(id: id, position: position, radius: radius) }
    }

    /// Assign or clear an exact stored bone name on one frozen explicit-edge set.
    /// - Parameters: `name` is unnormalized; `target` captures source, selection and constraint epochs.
    /// - Returns: The atomically committed snapshot; semantic no-ops retain history and preview inputs.
    /// - Throws: Stale target, cancellation or the original document validation/quota error.
    /// - Example: `try await session.assignBoneName("Root", target: target)`.
    public func assignBoneName(_ name: String, target: EdgeBoneAssignmentTarget) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard target.isCurrent(in: state.snapshot) else { throw EdgeBoneAssignmentError.staleTarget }
            try state.apply([.setEdgeBoneNames(ids: target.edgeIDs, name: name)])
        }.snapshot
    }

    /// Clear a captured global set of exact stored bone matches in one Undo step.
    /// - Parameter target: Frozen source, interaction epochs and matching edge IDs.
    /// - Returns: One metadata-only publication, preserving graph selection and preview inputs.
    /// - Throws: Stale target, cancellation or original document error before publication.
    /// - Example: `try await session.clearBoneAssignments(target: target)`.
    public func clearBoneAssignments(target: BoneAssignmentClearTarget) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard target.isCurrent(in: state.snapshot) else { throw BoneAssignmentClearError.staleTarget }
            try state.apply([.clearEdgeBoneNames(ids: target.edgeIDs)])
        }.snapshot
    }

    /// Replace transient graph selection with one captured bone-name or unassigned group.
    /// - Parameter target: Frozen source/interaction epochs and eligible exact edge IDs.
    /// - Returns: Current selection with document/history/preview inputs unchanged.
    /// - Throws: Stale target, cancellation or original selection error before publication.
    /// - Example: `try await session.selectBoneEdges(target: overview.target(for: .unassigned))`.
    public func selectBoneEdges(target: BoneEdgeSelectionTarget) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard target.isCurrent(in: state.snapshot) else { throw BoneEdgeSelectionError.staleTarget }
            try state.selectGraph(nodes: [], edges: target.selectableEdgeIDs)
        }.snapshot
    }

    /// Perform a captured inspector command after source/interaction validation on this window's actor.
    /// Deletion retains existing split/prune normalization; selection-only actions add no Undo entry.
    /// - Throws: Stale intent, cancellation or the original document error before atomic publication.
    public func performInspectorAction(target: GraphInspectorActionTarget) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) { state in
            guard target.isCurrent(in: state.snapshot), let action = target.action else {
                throw GraphInspectorActionError.staleTarget
            }
            func identifier() -> String { "{\(UUID().uuidString.lowercased())}" }
            let commands: [DocumentCommand]
            switch action {
            case .connect(let from, let to): commands = [.joinNodes(id: identifier(), from: from, to: to)]
            case .deleteNode(let id): commands = [.removeNode(id: id)]
            case .reverseEdge(let id): commands = [.reverseEdges([id])]
            case .repairEdgeDirections: commands = [.reverseEdges(target.edgeDirectionRepairs)]
            case .disconnectEdge(let id): commands = [.removeEdge(id: id)]
            case .selectEndpoints(let id):
                guard let edge = state.snapshot.edges.first(where: { $0.id.utf8.elementsEqual(id.utf8) }) else {
                    throw GraphInspectorActionError.staleTarget
                }
                try state.selectGraph(nodes: [edge.fromID, edge.toID], edges: [])
                return
            case .selectBoneEdges:
                try state.selectGraph(nodes: [], edges: target.boneEdgeIDs)
                return
            case .insertMidpoint:
                try state.insertSelectedEdgeMidpoint(nodeID: identifier(), edgeID: identifier())
                return
            }
            let prepared = try GraphCommandPreparation.normalizingDeletions(
                commands, document: state.snapshot.document)
            try state.apply(prepared)
        }.snapshot
    }

    /// Atomically apply a graph transaction; cancellation is checked before it begins.
    public func apply(_ commands: [DocumentCommand], selecting id: String? = nil) throws -> EditorSnapshot {
        try apply(commands, selecting: id, target: nil)
    }

    package func apply(
        _ commands: [DocumentCommand], selecting id: String?, target: CanvasAdjustmentTarget?
    ) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: target != nil) { state in
            if let target, !hasAcceptedSource || !target.isCurrent(in: state.snapshot) {
                throw EditorError.staleCanvasAdjustment
            }
            let prepared = try GraphCommandPreparation.normalizingDeletions(commands, document: state.snapshot.document)
            try state.apply(prepared, selecting: id)
        }.snapshot
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
        if onlyEditable {
            guard state.snapshot.canCutNodes else { throw EditorError.readOnlyNode }
            _ = try GraphCommandPreparation.normalizingDeletions(
                state.selectionDeletionCommands(), document: state.snapshot.document)
        }
        let nodes = state.snapshot.selectedNodes.filter { !onlyEditable || $0.isEditable }
        let fragment = try state.snapshot.document.copyingNodes(Set(nodes.map(\.id)))
        try Task.checkCancellation()
        return fragment
    }

    /// Copy a captured graph selection as plain Qt XML without changing history.
    package func copySelectionAsQtXML(target: CanvasAdjustmentTarget) throws -> Data {
        try Task.checkCancellation()
        guard hasAcceptedSource, let state, target.isCurrent(in: state.snapshot) else {
            throw EditorError.staleCanvasAdjustment
        }
        let snapshot = state.snapshot
        let xml = try snapshot.document.copyingNodesAsQtXML(Set(snapshot.selectedNodes.map(\.id)))
        try Task.checkCancellation()
        return xml
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
        try paste(snapshotXML: snapshotXML, parentID: nil, target: nil)
    }

    package func paste(snapshotXML: Data, parentID: String?, target: CanvasAdjustmentTarget?) throws -> EditorSnapshot {
        try validatePasteSource(parentID: parentID, target: target)
        return try pasteQtSnapshot(
            snapshotXML, allowsEmptyGraph: false, parentID: parentID, selectsEditableGraph: true,
            clearsMissingCutFaces: true)
    }

    /// Apply a selected XML file only to the source captured before presenting its picker.
    package func pasteQtXMLFile(
        _ snapshotXML: Data, target: CanvasAdjustmentTarget, parentID: String? = nil, selectsEditableGraph: Bool = true,
        clearsMissingCutFaces: Bool = false, settlesNewDocumentOrigin: Bool = false
    ) throws -> EditorSnapshot {
        try Task.checkCancellation()
        guard hasAcceptedSource, let state, target.isCurrent(in: state.snapshot) else {
            throw QtXMLFilePasteError.staleTarget
        }
        if let parentID, state.snapshot.addPlacementGroup(parentID) == nil {
            throw DocumentError.invalidComponentStructure
        }
        return try pasteQtSnapshot(
            snapshotXML, allowsEmptyGraph: true, parentID: parentID, selectsEditableGraph: selectsEditableGraph,
            clearsMissingCutFaces: clearsMissingCutFaces, settlesNewDocumentOrigin: settlesNewDocumentOrigin)
    }

    private func pasteQtSnapshot(
        _ snapshotXML: Data, allowsEmptyGraph: Bool, parentID: String?, selectsEditableGraph: Bool,
        clearsMissingCutFaces: Bool, settlesNewDocumentOrigin: Bool = false
    ) throws -> EditorSnapshot {
        try Task.checkCancellation()
        guard let state else { throw EditorError.notLoaded }
        guard let fragment = try Self.qtXMLFragment(snapshotXML, allowsEmptyGraph: allowsEmptyGraph) else {
            try Task.checkCancellation()
            return state.snapshot
        }
        let identifier: String
        if let previous = lastQtTransfer, previous.snapshot == snapshotXML {
            identifier = previous.identifier
        } else {
            identifier = Self.identifier()
        }
        let prepared =
            if clearsMissingCutFaces {
                try fragment.clearingMissingQtCutFaces(destinationPartIDs: state.snapshot.parts.map(\.id))
            } else {
                fragment
            }
        let payload = try NodeClipboardPayload(fragment: prepared, identifier: identifier)
        let next = try paste(
            payload: payload, parentID: parentID, selectsEditableGraph: selectsEditableGraph,
            settlesNewDocumentOrigin: settlesNewDocumentOrigin)
        lastQtTransfer = (Data(snapshotXML), identifier)
        return next
    }

    /// Validate launch input before creating any of its destination windows.
    package func validateQtXMLFile(_ snapshotXML: Data) throws {
        try Task.checkCancellation()
        _ = try Self.qtXMLFragment(snapshotXML, allowsEmptyGraph: true)
        try Task.checkCancellation()
    }

    private static func qtXMLFragment(_ snapshotXML: Data, allowsEmptyGraph: Bool) throws -> NodeClipboard? {
        let document = try Dust3DDocument(snapshotXML: snapshotXML)
        let contents = try document.editorContents()
        if allowsEmptyGraph, contents.nodes.isEmpty, contents.edges.isEmpty, contents.parts.isEmpty,
            try document.components().isEmpty
        {
            return nil
        }
        return try NodeClipboard(document: document, selectedNodeIDs: Set(contents.nodes.map(\.id)))
    }

    /// Paste fresh graph identities and normalize copied groups in one undo transaction.
    /// Successive pastes move by 0.04 on Y/Z; placement bookkeeping is transient and resets on Open.
    /// - Parameter data: Bytes produced by `copyPayload(identifier:onlyEditable:)`.
    /// - Returns: The committed snapshot with only explicitly copied nodes selected.
    /// - Throws: Load, transport, archive or graph validation errors atomically; failed pastes do not advance placement.
    public func paste(data: Data) throws -> EditorSnapshot {
        try paste(data: data, parentID: nil, target: nil)
    }

    package func paste(data: Data, parentID: String?, target: CanvasAdjustmentTarget?) throws -> EditorSnapshot {
        try validatePasteSource(parentID: parentID, target: target)
        return try paste(payload: NodeClipboardPayload(data: data), parentID: parentID)
    }

    private func validatePasteSource(parentID: String?, target: CanvasAdjustmentTarget?) throws {
        try Task.checkCancellation()
        guard let state else { throw EditorError.notLoaded }
        if let target, !hasAcceptedSource || !target.isCurrent(in: state.snapshot) {
            throw WorkingGroupPasteError.staleTarget
        }
        if let parentID, state.snapshot.addPlacementGroup(parentID) == nil {
            throw DocumentError.invalidComponentStructure
        }
    }

    private func paste(
        payload: NodeClipboardPayload, parentID: String?, selectsEditableGraph: Bool = false,
        settlesNewDocumentOrigin: Bool = false
    ) throws -> EditorSnapshot {
        guard let state else { throw EditorError.notLoaded }
        let fragment = payload.fragment
        let contents = try fragment.document.editorContents()
        let sourceNodes = Set(contents.nodes.map(\.id))
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
        var commands: [DocumentCommand] = [
            .pasteNodes(
                clipboard: fragment, identities: identities,
                offset: .init(x: 0, y: distance, z: distance), partitions: partitions)
        ]
        if settlesNewDocumentOrigin, state.snapshot.nodes.isEmpty, !contents.nodes.isEmpty {
            let center = try OriginSettlement.center(of: contents.nodes.map(\.value))
            commands.append(.setOrigin(.init(x: center.x, y: center.y + distance, z: center.z + distance)))
        }
        let next = try updateWithResult(checkCancellationBeforePublication: true) { state in
            try state.apply(commands, pasteParentID: parentID)
            if selectsEditableGraph {
                let snapshot = state.snapshot
                let pastedEdges = Set(contents.edges.compactMap { identities[$0.id] })
                let editableNodes = Set(snapshot.nodes.filter(\.isEditable).map(\.id))
                let editableEdges = Set(snapshot.editableEdges.map(\.id))
                try state.selectGraph(
                    nodes: selected.intersection(editableNodes), edges: pastedEdges.intersection(editableEdges))
            } else {
                try state.select(selected)
            }
        }.snapshot
        lastPasteIdentifier = payload.identifier
        pasteOrdinal = ordinal + 1
        return next
    }

    /// Atomically place/connect one captured visible ghost with fresh identities and return its chaining receipt.
    /// - Parameter request: Pure Add-mode click captured after pointer preview became visible.
    /// - Returns: One accepted snapshot/outcome; duplicates preserve document/history and selection.
    /// - Throws: Cancellation, load, stale or typed placement validation errors without publication.
    public func placeAddNode(_ request: AddPlacementRequest) throws -> AddPlacementReceipt {
        try Task.checkCancellation()
        guard var next = state else { throw EditorError.notLoaded }
        guard hasAcceptedSource else { throw EditorError.staleAddPlacement }
        let result = try next.placeAddNode(
            request,
            identities: .init(
                nodeID: Self.identifier(), partID: Self.identifier(),
                componentID: Self.identifier(), edgeID: Self.identifier()))
        try Task.checkCancellation()
        state = next
        return AddPlacementReceipt(
            snapshot: next.snapshot, outcome: result.outcome, contextID: request.contextID,
            connectionFallbackReason: result.connectionFallbackReason)
    }

    private static func identifier() -> String { "{\(UUID().uuidString.lowercased())}" }

    /// Clear selected node-owned part color overrides in one transaction, without preparing an image.
    /// - Returns: The current snapshot; no-op plans retain history and preview identities.
    /// - Throws: Load, cancellation, stale or ownership errors atomically.
    public func clearSelectedPartColors(target: CanvasAdjustmentTarget? = nil) throws -> EditorSnapshot {
        try updateWithResult(checkCancellationBeforePublication: true) {
            _ = try $0.clearSelectedPartColors(target: target)
        }.snapshot
    }

    /// Apply one source-verified fitted-raster color plan on the editing actor.
    /// - Parameters: Owned source bytes/raster and frozen displayed layout; target captures pre-await epochs.
    /// - Returns: Snapshot and skip/change statistics for this one atomic transaction.
    /// - Throws: Load, cancellation, stale source/context or ownership errors without a partial edit.
    public func autoColorSelectedParts(
        raster: ReferenceColorRaster, layout: ReferenceColorSamplingLayout,
        referencePNG: Data, target: ReferenceColorTarget
    ) throws -> ReferenceColorReceipt {
        guard let previous = state?.snapshot else { throw EditorError.notLoaded }
        let result = try updateWithResult(checkCancellationBeforePublication: true) {
            try $0.autoColorSelectedParts(raster: raster, layout: layout, referencePNG: referencePNG, target: target)
        }
        return ReferenceColorReceipt(snapshot: result.snapshot, plan: result.result, previous: previous)
    }

    public func undo() throws -> EditorSnapshot { try update { try $0.undo() } }
    public func redo() throws -> EditorSnapshot { try update { try $0.redo() } }

    private func update(_ operation: (inout EditorState) throws -> Void) throws -> EditorSnapshot {
        try updateWithResult(operation).snapshot
    }

    private func updateWithResult<Result>(
        checkCancellationBeforePublication: Bool = false,
        _ operation: (inout EditorState) throws -> Result
    ) throws
        -> (snapshot: EditorSnapshot, result: Result)
    {
        try Task.checkCancellation()
        guard var next = state else { throw EditorError.notLoaded }
        let result = try operation(&next)
        // Stage selection pruning with the edit so cancellation cannot publish either change.
        let nextAnimationID = selectedAnimationID.flatMap {
            Self.animationSnapshot(next, selectedID: $0).list.selectedRow?.source.id
        }
        if checkCancellationBeforePublication { try Task.checkCancellation() }
        selectedAnimationID = nextAnimationID
        state = next
        return (next.snapshot, result)
    }
}

private enum ComponentGroupingError: LocalizedError {
    case staleTarget

    var errorDescription: String? { "The document or component selection changed. Group the components again." }
}

package enum WorkingGroupPasteError: LocalizedError, Equatable, Sendable {
    case staleTarget

    package var errorDescription: String? { "The clipboard destination changed. Paste again." }
}

package enum QtXMLFilePasteError: LocalizedError, Equatable, Sendable {
    case staleTarget

    package var errorDescription: String? { "The XML paste destination changed. Choose the file again." }
}
