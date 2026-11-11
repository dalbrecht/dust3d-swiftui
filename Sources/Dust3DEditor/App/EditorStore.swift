import AppKit
import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Dust3DRendering
import Foundation
import Observation
import os

@MainActor @Observable
final class EditorStore {
    private(set) var snapshot: EditorSnapshot? {
        didSet {
            if isSelectingRigEdges, snapshot?.selectedIDs.isEmpty == false {
                changeRigEdgeSelection(false)
            }
            if componentBrowseGroupID != nil { reconcileComponentBrowse(previous: oldValue) }
            if let hover = boneEdgeHover, snapshot.map({ !hover.target.isCurrent(in: $0) }) ?? true {
                boneEdgeHover = nil
            }
            if let motion = canvasProfileMotion, snapshot.map({ motion.isCurrent(in: $0) }) != true {
                canvasProfileMotion = nil
            }
            if oldValue?.documentIdentity != snapshot?.documentIdentity { clearCanvasHover() }
            if case .group(let id) = addPlacementDestination, snapshot?.addPlacementGroup(id) == nil {
                changeAddPlacementDestination(.documentRoot)
            }
            if let snapshot, isAddingNodes, !addPlacement.isCurrent(in: snapshot) { cancelAddMode() }
            if oldValue?.documentRevision != snapshot?.documentRevision {
                if !preservesCanvasPartStateHover { canvasPartStateHover = nil }
                if case .edge = canvasGraphHover { canvasGraphHover = nil }
            }
            if let hoveredNodeID, snapshot?.nodes.contains(where: { $0.id == hoveredNodeID && $0.isVisible }) != true {
                clearCanvasHover()
            }
        }
    }
    private(set) var isSelectingGraph = false
    var canPickGraph: Bool { acceptedDocumentSource != nil && (!isWorking || isSelectingGraph) }
    private(set) var isSelectingRigEdges = false
    private(set) var rigEdgeSelectionEpoch = UUID()
    var canChangeRigEdgeSelection: Bool {
        !isWorking && !isAddingNodes && !isMovingOrigin && acceptedDocumentSource != nil
    }

    func rigEdgeSelectionToggleAction() -> @MainActor (Bool) -> Void {
        let target = snapshot.map(CanvasAdjustmentTarget.init)
        let epoch = rigEdgeSelectionEpoch
        return { [weak self] enabled in
            guard let self, let current = self.acceptedDocumentSource, target?.isCurrent(in: current) == true,
                self.rigEdgeSelectionEpoch == epoch
            else { return }
            self.setRigEdgeSelection(enabled)
        }
    }

    func setRigEdgeSelection(_ enabled: Bool) {
        guard canChangeRigEdgeSelection, enabled != isSelectingRigEdges, let snapshot else { return }
        changeRigEdgeSelection(enabled)
        let nodes = snapshot.selectedIDs
        guard enabled, !nodes.isEmpty else { return }
        let epoch = rigEdgeSelectionEpoch
        perform(
            commits: false, selectionOnly: true,
            completion: { [weak self] succeeded in
                if !succeeded, let self, self.rigEdgeSelectionEpoch == epoch { self.changeRigEdgeSelection(false) }
            },
            { try await $0.removeFromSelection(nodes: nodes, edges: []) })
    }

    private func changeRigEdgeSelection(_ enabled: Bool) {
        guard enabled != isSelectingRigEdges else { return }
        isSelectingRigEdges = enabled
        rigEdgeSelectionEpoch = UUID()
        rotationInputContextID = UUID()
        pendingWholePartPick = nil
        canvasProfileMotion = nil
        clearCanvasHover()
    }

    func admitsCanvasSelectionInput(epoch: UUID, lease: UUID?) -> Bool {
        rigEdgeSelectionEpoch == epoch && ownsCanvasProfile(lease)
    }

    struct CanvasNodeSelectionTarget {
        fileprivate let context: PartGraphSelectionContext
        fileprivate let profileLease: UUID?
        fileprivate let selectionEpoch: UUID
        fileprivate let addModeID: UUID
        fileprivate let toolEpoch: UUID
    }

    func canvasNodeSelectionTarget(profileLease: UUID?) -> CanvasNodeSelectionTarget? {
        guard canPickGraph, !isSelectingRigEdges, !isAddingNodes, !isMovingOrigin,
            ownsCanvasProfile(profileLease), let snapshot
        else { return nil }
        return CanvasNodeSelectionTarget(
            context: PartGraphSelectionContext(snapshot: snapshot), profileLease: profileLease,
            selectionEpoch: rigEdgeSelectionEpoch, addModeID: addModeID, toolEpoch: rotationInputContextID)
    }

    private func admitsCanvasNodeSelection(_ target: CanvasNodeSelectionTarget) -> Bool {
        canPickGraph && !isSelectingRigEdges && !isAddingNodes && !isMovingOrigin
            && admitsCanvasSelectionInput(epoch: target.selectionEpoch, lease: target.profileLease)
            && addModeID == target.addModeID && rotationInputContextID == target.toolEpoch
            && snapshot.map { target.context.isCurrent(in: $0) } == true
    }

    func canvasNodeSidebarPresentation(profileLease: UUID?) -> CanvasNodeSidebarPresentation? {
        guard !isWorking, let snapshot, let target = canvasNodeSelectionTarget(profileLease: profileLease) else {
            return nil
        }
        return CanvasNodeSidebarPresentation(snapshot: snapshot, profileLease: profileLease, target: target)
    }

    @discardableResult
    func selectCanvasSidebarNodes(
        _ ids: Set<String>, matching query: String, in presentation: CanvasNodeSidebarPresentation
    ) -> Bool {
        guard admitsCanvasNodeSidebarSelection(presentation) else { return false }
        let rows = presentation.rows(matching: query)
        let displayed = Set(rows.map(\.id))
        let displayedSelection = presentation.selectedIDs.intersection(displayed)
        let displayedKeys = Set(displayed.map { Data($0.utf8) })
        guard ids.allSatisfy({ displayedKeys.contains(Data($0.utf8)) }), ids != displayedSelection else { return false }
        if ids.isEmpty {
            perform(commits: false, selectionOnly: true) {
                try await $0.removeFromSelection(nodes: displayedSelection, edges: [])
            }
        } else {
            select(ids)
        }
        return true
    }

    @discardableResult
    func selectAllCanvasSidebarNodes(matching query: String, in presentation: CanvasNodeSidebarPresentation) -> Bool {
        guard admitsCanvasNodeSidebarSelection(presentation) else { return false }
        let ids = Set(presentation.rows(matching: query).map(\.id))
        guard !ids.isEmpty else { return false }
        select(ids)
        return true
    }

    private func admitsCanvasNodeSidebarSelection(_ presentation: CanvasNodeSidebarPresentation) -> Bool {
        !isWorking && admitsCanvasNodeSelection(presentation.target)
            && snapshot?.selectionRevision == presentation.selectionRevision
    }

    func activateCanvasNode(_ id: String, action: CanvasNodeSelectionAction, target: CanvasNodeSelectionTarget?) {
        guard let target, admitsCanvasNodeSelection(target) else { return }
        switch action {
        case .wholePart: selectWholePart(.node(id), context: target.context)
        case .selection(.replace): select(id)
        case .selection(.toggle): toggleSelection(id)
        case .selection(let mode): selectGraph(nodes: [id], edges: [], mode: mode)
        }
    }

    private struct PendingWholePartPick {
        let target: PartGraphTarget
        let context: PartGraphSelectionContext
        let documentIdentity: UUID
        let documentRevision: Int
    }
    private var pendingWholePartPick: PendingWholePartPick?
    func canSelectWholePart(_ target: PartGraphTarget) -> Bool {
        !isSelectingRigEdges && canPickGraph && snapshot?.canSelectWholePart(target) == true
    }
    var wholePartActionTarget: PartGraphTarget? {
        if !isAddingNodes, let hoveredNodeID { return .node(hoveredNodeID) }
        guard let snapshot else { return nil }
        if let id = snapshot.selectedPartID { return .part(id) }
        if snapshot.selectedIDs.count == 1, snapshot.selectedEdgeIDs.isEmpty, let id = snapshot.selectedID {
            return .node(id)
        }
        if snapshot.selectedIDs.isEmpty, let id = snapshot.selectedEdgeID { return .edge(id) }
        return nil
    }
    /// Build a targeted view action from the rendered document, never from a later replacement.
    func wholePartSelectionAction(_ target: PartGraphTarget) -> @MainActor () -> Void {
        let context = snapshot.map { PartGraphSelectionContext(snapshot: $0) }
        let epoch = rigEdgeSelectionEpoch
        return { [weak self] in
            guard let self, let context, self.rigEdgeSelectionEpoch == epoch else { return }
            self.selectWholePart(target, context: context)
        }
    }
    @ObservationIgnored private var graphComponentRevealLookup: GraphComponentRevealLookup?

    func revealOwningComponentAction(
        _ target: PartGraphTarget, context: PartGraphSelectionContext?, profileLease: UUID? = nil
    ) -> (@MainActor () -> Void)? {
        guard let context, let source = revealSource(context: context, profileLease: profileLease) else { return nil }
        if graphComponentRevealLookup?.isCurrent(in: source) != true {
            graphComponentRevealLookup = GraphComponentRevealLookup(snapshot: source)
        }
        guard graphComponentRevealLookup?.contains(target, in: source) == true else { return nil }
        let modeID = addModeID
        return { [weak self] in
            guard let self, self.addModeID == modeID,
                let current = self.revealSource(context: context, profileLease: profileLease),
                current.canRevealOwningComponent(target)
            else { return }
            self.perform(commits: false) { try await $0.revealOwningComponent(target, context: context) }
        }
    }

    private func revealSource(context: PartGraphSelectionContext, profileLease: UUID?) -> EditorSnapshot? {
        guard ownsCanvasProfile(profileLease), !isWorking, !isAddingNodes, !isMovingOrigin,
            let source = acceptedDocumentSource, context.isCurrent(in: source)
        else { return nil }
        return source
    }

    func selectComponentGraph(_ target: ComponentGraphSelectionTarget) {
        guard !isSelectingRigEdges, !stopped, !isWorking, snapshot?.canSelectComponentGraph(target) == true else {
            return
        }
        cancelAddMode()
        perform(commits: false, selectionOnly: true) { try await $0.selectComponentGraph(target) }
    }
    func selectWholePart(_ target: PartGraphTarget, context: PartGraphSelectionContext? = nil) {
        guard !isSelectingRigEdges, canPickGraph, let snapshot, context?.isCurrent(in: snapshot) != false,
            snapshot.canSelectWholePart(target)
        else { return }
        let pick = PendingWholePartPick(
            target: target, context: context ?? .init(snapshot: snapshot), documentIdentity: snapshot.documentIdentity,
            documentRevision: snapshot.documentRevision)
        if isWorking && isSelectingGraph {
            pendingWholePartPick = pick
            return
        }
        commitWholePartPick(pick)
    }
    private func commitWholePartPick(_ pick: PendingWholePartPick) {
        guard !stopped, !isWorking, let snapshot,
            snapshot.documentIdentity == pick.documentIdentity, snapshot.documentRevision == pick.documentRevision
        else { return }
        cancelAddMode()
        perform(commits: false, selectionOnly: true) {
            try await $0.selectWholePart(pick.target, context: pick.context)
        }
    }
    private func drainWholePartPick() {
        let pick = pendingWholePartPick
        pendingWholePartPick = nil
        if let pick { commitWholePartPick(pick) }
    }
    func selectWholePart(at point: CanvasPoint, projection: CanvasProjection, context: PartGraphSelectionContext? = nil)
    {
        guard !isSelectingRigEdges, canPickGraph, !isAddingNodes, let snapshot,
            context?.isCurrent(in: snapshot) != false
        else { return }
        if let node = snapshot.nodes.last(where: {
            let center = projection.point(for: $0.value.position)
            return $0.isVisible && hypot(center.x - point.x, center.y - point.y) <= 18
        }) {
            selectWholePart(.node(node.id), context: context)
        } else if let edge = projection.edgeID(near: point, nodes: snapshot.nodes, edges: snapshot.edges) {
            selectWholePart(.edge(edge), context: context)
        }
    }
    func partNodesSelectionAction(_ id: String) -> @MainActor () -> Void {
        let context = snapshot.map { PartGraphSelectionContext(snapshot: $0) }
        let epoch = rigEdgeSelectionEpoch
        return { [weak self] in
            guard let self, let context, self.rigEdgeSelectionEpoch == epoch else { return }
            self.selectPartNodes(id, context: context)
        }
    }
    func selectPartNodes(_ id: String, context: PartGraphSelectionContext? = nil) {
        guard !isSelectingRigEdges, !isWorking, !stopped, let snapshot,
            context?.isCurrent(in: snapshot) != false
        else { return }
        let capturedContext = context ?? PartGraphSelectionContext(snapshot: snapshot)
        perform(commits: false, selectionOnly: true) { try await $0.selectPartNodes(id, context: capturedContext) }
    }
    private(set) var addPlacement = AddPlacementState()
    private(set) var addModeID = UUID()
    private var canvasWidth: Double = 0
    private var canvasGeometryUsesProfileLease = false
    private var addPlacementRequestID: UUID?
    private(set) var addPlacementNotice: String?
    private let addPlacements: any AddPlacementServing
    var isAddingNodes: Bool { addPlacement.isActive }
    var addGhostPoint: CanvasPoint? { addPlacement.ghostPoint }
    var addGhostRadius: Double { addPlacement.sceneRadius }
    var addGhostModelRadius: Double {
        addPlacement.canvasHeight > 0 ? addPlacement.sceneRadius / addPlacement.canvasHeight : 0
    }
    var addRadiusLimitNotice: String? {
        guard let committed = addPlacement.wouldCommitRadius, committed != addGhostModelRadius else { return nil }
        return "Node radius will be limited to \(committed.formatted(.number.precision(.fractionLength(0...4))))."
    }
    var addGhostDisplayDiameter: Double {
        guard let projection = frozenAddProjection else { return 0 }
        return max(8, min(addGhostModelRadius * projection.scale * 2, 600))
    }
    var addAnchorIsReadOnly: Bool {
        guard let anchor = addPlacement.anchorID else { return false }
        return snapshot?.nodes.first { $0.id == anchor }?.isEditable != true
    }
    var frozenAddProjection: CanvasProjection? { addPlacement.isActive ? addPlacement.projection : nil }
    var addAnchorPosition: NodePosition? { snapshot?.nodes.first { $0.id == addPlacement.anchorID }?.value.position }
    var canBeginAddMode: Bool {
        !isSelectingRigEdges && acceptedAddPlacementSource != nil && canvasWidth > 0 && canvasHeight > 0
    }
    var canPlaceAddGhost: Bool {
        guard isAddingNodes, acceptedAddPlacementSource != nil, addGhostPoint != nil else { return false }
        return addPlacement.anchorID == nil
            || snapshot?.nodes.first { $0.id == addPlacement.anchorID }?.isEditable == true
    }
    func setCanvasContext(
        projection: CanvasProjection, width: Double, height: Double, lease: UUID? = nil
    ) {
        guard ownsCanvasProfile(lease), lease == nil || projection.plane == plane else { return }
        canvasGeometryUsesProfileLease = lease != nil
        if isAddingNodes, frozenAddProjection == nil {
            guard projection.plane == plane, width.isFinite, width > 0, height.isFinite, height > 0,
                let snapshot
            else { return }
            do {
                try addPlacement.reproject(snapshot: snapshot, projection: projection, canvasHeight: height)
            } catch {
                cancelAddMode()
                errorMessage = Self.message(error)
                return
            }
        } else if isAddingNodes && (canvasWidth != width || canvasHeight != height) {
            cancelAddMode()
        }
        updatePrecisionCanvasIdentity(projection: projection, width: width, height: height)
        canvasWidth = width
        setCanvasHeight(height)
        // Mode entry rebuilds against current bounds/plane, which may change before SwiftUI renders again.
        if !projection.scale.isFinite { canvasWidth = 0 }
    }
    private(set) var addPlacementDestination = AddPlacementDestination.selection
    private var workingGroupRevision = UUID()

    private var acceptedAddPlacementSource: EditorSnapshot? {
        guard canSave, case .success(let accepted) = recoveryLoadResult, let snapshot,
            accepted.documentIdentity == snapshot.documentIdentity
        else { return nil }
        return snapshot
    }

    var canChooseAddPlacementDestination: Bool { acceptedAddPlacementSource != nil }

    private var effectiveAddPlacementDestination: AddPlacementDestination {
        if addPlacementDestination == .selection, let componentBrowseGroupID {
            return .group(componentBrowseGroupID)
        }
        return addPlacementDestination
    }

    var addPlacementDestinationTitle: String {
        switch effectiveAddPlacementDestination {
        case .selection: "Selected group or root for pointer Add"
        case .documentRoot: "Document root"
        case .group(let id): snapshot?.addPlacementGroup(id)?.title ?? "Unavailable group"
        }
    }

    private func capturedAddPlacementAction(
        snapshot: EditorSnapshot?,
        perform action: @escaping @MainActor (EditorStore, EditorSnapshot) -> Void
    ) -> @MainActor () -> Void {
        guard let snapshot else { return {} }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        let revision = workingGroupRevision
        return { [weak self] in
            guard let self, self.workingGroupRevision == revision,
                let current = self.acceptedAddPlacementSource, target.isCurrent(in: current)
            else { return }
            action(self, current)
        }
    }

    func workingGroupAction(
        _ destination: AddPlacementDestination, snapshot: EditorSnapshot
    ) -> @MainActor () -> Void {
        capturedAddPlacementAction(snapshot: snapshot) { store, current in
            if case .group(let id) = destination, current.addPlacementGroup(id) == nil { return }
            store.changeAddPlacementDestination(destination)
        }
    }

    func addPlacementToggleAction() -> @MainActor (Bool) -> Void {
        let begin = capturedAddPlacementAction(snapshot: acceptedAddPlacementSource) { store, _ in
            store.beginAddMode()
        }
        let modeID = addModeID
        return { [weak self] active in
            if active {
                begin()
            } else if let self, self.addModeID == modeID {
                self.cancelAddMode()
            }
        }
    }

    private func changeAddPlacementDestination(_ destination: AddPlacementDestination) {
        guard addPlacementDestination != destination else { return }
        addPlacementDestination = destination
        workingGroupRevision = UUID()
        cancelAddMode()
    }

    func beginAddMode() {
        guard canBeginAddMode, let snapshot = acceptedAddPlacementSource else { return }
        cancelReferenceColorCommit()
        let currentCanvasProjection = CanvasProjection(
            bounds: bounds, plane: plane, width: canvasWidth, height: canvasHeight)
        cancelOriginDrag()
        isMovingOrigin = false
        do {
            addPlacementNotice = nil
            try addPlacement.begin(
                snapshot: snapshot, projection: currentCanvasProjection, canvasHeight: canvasHeight,
                destination: effectiveAddPlacementDestination)
            addModeID = UUID()
        } catch { errorMessage = Self.message(error) }
    }
    func cancelAddMode(refit: Bool = true) {
        guard isAddingNodes else { return }
        if addPlacementRequestID != nil { operation?.cancel() }
        addPlacementRequestID = nil
        addPlacement.cancel()
        addPlacementNotice = nil
        addModeID = UUID()
        if refit { fitCanvas() }
    }
    func previewAddAtCanvasCenter() {
        updateAddPointer(at: .init(x: canvasWidth / 2, y: canvasHeight / 2), modeID: addModeID)
    }
    func nudgeAddPreview(x: Double, y: Double) {
        guard let point = addGhostPoint else { return }
        updateAddPointer(at: .init(x: point.x + x, y: point.y + y), modeID: addModeID)
    }
    var canAdjustRadiusInput: Bool { isAddingNodes ? !isWorking && addGhostPoint != nil : canAdjustSelectionRadius }
    func updateAddPointer(at point: CanvasPoint?, modeID: UUID) {
        guard isAddingNodes, modeID == addModeID else { return }
        guard let point else {
            addPlacement.hideGhost()
            return
        }
        do { try addPlacement.updatePointer(point) } catch { errorMessage = Self.message(error) }
    }
    func placeAddNode(at point: CanvasPoint, modeID: UUID) {
        guard modeID == addModeID, canPlaceAddGhost, let snapshot = acceptedAddPlacementSource,
            let projection = frozenAddProjection
        else { return }
        do {
            try addPlacement.updatePointer(point)
            let candidate = addConnectionCandidate(at: point, projection: projection, snapshot: snapshot)
            guard let request = addPlacement.request(connectingTo: candidate) else { return }
            let placementID = UUID()
            addPlacementRequestID = placementID
            let service = addPlacements
            perform(
                acceptCommittedCancellation: true,
                completion: { [weak self] _ in
                    guard let self, self.addPlacementRequestID == placementID else { return }
                    self.addPlacementRequestID = nil
                    if !self.isAddingNodes { self.fitCanvas() }
                },
                { [weak self] session in
                    let receipt = try await service.place(request, in: session)
                    await self?.acceptAddPlacement(receipt, modeID: modeID)
                    return receipt.snapshot
                })
        } catch { errorMessage = Self.message(error) }
    }
    private func addConnectionCandidate(
        at point: CanvasPoint, projection: CanvasProjection, snapshot: EditorSnapshot
    ) -> String? {
        var candidate: String?
        var nearestDistance = 18.0
        var centers: [Data: CanvasPoint] = [:]
        for node in snapshot.nodes where node.isVisible {
            let center = projection.point(for: node.value.position)
            centers[Data(node.id.utf8)] = center
            let distance = hypot(center.x - point.x, center.y - point.y)
            // On an exact tie the later, topmost node keeps precedence.
            if distance <= nearestDistance {
                nearestDistance = distance
                candidate = node.id
            }
        }
        guard let candidate else { return nil }
        for edge in snapshot.edges {
            guard let from = centers[Data(edge.fromID.utf8)], let to = centers[Data(edge.toID.utf8)] else { continue }
            let dx = to.x - from.x
            let dy = to.y - from.y
            let length = hypot(dx, dy)
            guard length > 0, length.isFinite else { continue }
            let x = point.x - from.x
            let y = point.y - from.y
            let ux = dx / length
            let uy = dy / length
            let along = x * ux + y * uy
            // Qt's directed edge triangle tapers from four points wide to zero.
            guard along >= 0, along <= length,
                abs(x * uy - y * ux) <= 2 * (1 - along / length)
            else { continue }
            if hypot(x - dx / 2, y - dy / 2) < nearestDistance { return nil }
        }
        return candidate
    }

    private func acceptAddPlacement(_ receipt: AddPlacementReceipt, modeID: UUID) {
        guard isAddingNodes, modeID == addModeID else { return }
        do {
            try addPlacement.accept(receipt)
            addPlacementNotice = receipt.connectionFallbackReason
            if !isAddingNodes { addModeID = UUID() }
        } catch {
            cancelAddMode(refit: false)
            errorMessage = Self.message(error)
        }
    }
    private(set) var canvasHeight: Double = 0
    @ObservationIgnored private var canvasGraphHoverCache = CanvasGraphHover.Cache()
    private var canvasPartStateHoverEpoch = UUID()
    @ObservationIgnored private var canvasPartStateHoverOperation: UUID?
    private var preservesCanvasPartStateHover: Bool { canvasPartStateHoverOperation == operationRequestID }
    var tracksPartStateHoverWhileWorking: Bool { isWorking && preservesCanvasPartStateHover }
    private var canvasPartStateHover: CanvasGraphHover? {
        didSet {
            if oldValue != canvasPartStateHover { canvasPartStateHoverEpoch = UUID() }
        }
    }
    private(set) var canvasGraphHover: CanvasGraphHover?
    var hoveredNodeID: String? {
        if case .node(let id) = canvasGraphHover { return id }
        return nil
    }
    func setCanvasHeight(_ height: Double) {
        let next = height.isFinite && height > 0 ? height : 0
        if next != canvasHeight {
            precisionLayoutEpoch = UUID()
            canvasPartStateHover = nil
        }
        canvasHeight = next
    }
    private func updatePrecisionCanvasIdentity(projection: CanvasProjection, width: Double, height: Double) {
        let next = ReferenceColorCanvasIdentity(projection: projection, width: width, height: height)
        if next != precisionCanvasIdentity {
            precisionLayoutEpoch = UUID()
            precisionCanvasIdentity = next
            canvasPartStateHover = nil
        }
    }

    private var currentCanvasProjection: CanvasProjection {
        CanvasProjection(bounds: bounds, plane: plane, width: canvasWidth, height: canvasHeight)
    }

    func setHoveredNode(_ id: String?, projection: CanvasProjection? = nil) {
        let visibleID = snapshot?.nodes.first(where: { $0.id == id && $0.isVisible })?.id
        canvasGraphHover = visibleID.map(CanvasGraphHover.node)
        if projection == nil || projection == currentCanvasProjection { canvasPartStateHover = canvasGraphHover }
    }

    func clearCanvasHover() {
        canvasGraphHover = nil
        canvasPartStateHover = nil
    }

    func updateCanvasHover(at point: CanvasPoint?, projection: CanvasProjection) {
        guard let point, let snapshot else {
            clearCanvasHover()
            return
        }
        let hover = canvasGraphHoverCache.hit(
            at: point, projection: projection, snapshot: snapshot, rigEdgesOnly: isSelectingRigEdges)
        if !tracksPartStateHoverWhileWorking, hover != canvasGraphHover { canvasGraphHover = hover }
        if projection == currentCanvasProjection { canvasPartStateHover = hover }
    }
    var canAdjustSelectionRadius: Bool {
        !isSelectingRigEdges && canSave && canvasHeight > 0 && snapshot?.canAdjustSelectionRadius == true
    }
    func adjustSelectionRadius(direction: Double) {
        if isAddingNodes {
            guard !isWorking, direction.isFinite, direction != 0 else { return }
            do { try addPlacement.adjustRadius(by: direction > 0 ? 1 : -1) } catch {
                errorMessage = Self.message(error)
            }
            return
        }
        guard canAdjustSelectionRadius, direction.isFinite, direction != 0, let snapshot else { return }
        let delta = (direction > 0 ? 1.0 : -1.0) / canvasHeight
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        perform { try await $0.adjustSelectionRadius(by: delta, target: target) }
    }
    private enum GraphWheelEdit: Sendable {
        case selectionRadius(Double)
        case nodeRadius(String, Double)
        case spacing(Double)

        var usesHover: Bool {
            if case .nodeRadius = self { return true }
            return false
        }
    }

    private struct GraphWheelScope: Equatable {
        let document: UUID
        let selection: Int
        let constraints: Int
        let lease: UUID?
        let layout: UUID
        let tool: UUID
        let interaction: UUID
        let hover: UUID?
    }

    private struct GraphWheelQueue {
        let id = UUID()
        let scope: GraphWheelScope
        var revision: Int
        var operation: UUID?
        var pending: [GraphWheelEdit] = []
    }

    @ObservationIgnored private var graphWheelQueue: GraphWheelQueue?

    var canRouteGraphWheelWhileWorking: Bool {
        isWorking && graphWheelQueue?.operation == operationRequestID
    }

    func handleCanvasWheel(_ input: CanvasWheelInput, profileLease: UUID? = nil) -> Bool {
        guard input.isSupported, ownsCanvasProfile(profileLease), !isSelectingRigEdges else { return false }
        if isAddingNodes {
            guard !isWorking, addGhostPoint != nil else { return false }
            adjustSelectionRadius(direction: input.verticalDelta)
            return true
        }
        guard let snapshot = acceptedDocumentSource, admitsGraphWheel else { return false }
        let step = (input.verticalDelta > 0 ? 1.0 : -1.0) / canvasHeight
        let edit: GraphWheelEdit
        let hasGraphSelection = !snapshot.selectedIDs.isEmpty || !snapshot.selectedEdgeIDs.isEmpty
        if hasGraphSelection && input.modifiers.contains(.command) {
            guard snapshot.transformNodes.contains(where: \.isEditable) else { return false }
            edit = .spacing(1 + step)
        } else if hasGraphSelection && snapshot.canAdjustSelectionRadius {
            edit = .selectionRadius(step)
        } else {
            let hover = isWorking ? canvasPartStateHover : canvasGraphHover
            guard case .node(let id) = hover, snapshot.canAdjustNodeRadius(id: id) else { return false }
            edit = .nodeRadius(id, step)
        }

        let scope = graphWheelScope(snapshot, lease: profileLease, usesHover: edit.usesHover)
        if let queue = graphWheelQueue {
            guard canRouteGraphWheelWhileWorking, queue.scope == scope,
                queue.revision == snapshot.documentRevision
            else { return false }
            // A recognized excess sample must not fall through to a different scroll command.
            if queue.pending.count < 32 { graphWheelQueue?.pending.append(edit) }
            return true
        }
        guard !isWorking else { return false }
        graphWheelQueue = GraphWheelQueue(scope: scope, revision: snapshot.documentRevision)
        dispatchGraphWheel(edit, snapshot: snapshot)
        return true
    }

    private var admitsGraphWheel: Bool {
        !isSelectingRigEdges && !isAddingNodes && !isMovingOrigin && !referenceColorInteractionActive
            && originDrag == nil && canvasProfileMotion == nil && canvasHeight > 0
    }

    private func graphWheelScope(_ snapshot: EditorSnapshot, lease: UUID?, usesHover: Bool) -> GraphWheelScope {
        GraphWheelScope(
            document: snapshot.documentIdentity, selection: snapshot.selectionRevision,
            constraints: snapshot.constraintRevision, lease: lease, layout: precisionLayoutEpoch,
            tool: rotationInputContextID, interaction: referenceColorInteractionEpoch,
            hover: usesHover ? canvasPartStateHoverEpoch : nil)
    }

    private func dispatchGraphWheel(_ edit: GraphWheelEdit, snapshot: EditorSnapshot) {
        guard let queue = graphWheelQueue else { return }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        perform(
            acceptCommittedCancellation: true, preservePartStateHover: edit.usesHover,
            completion: { [weak self] succeeded in
                guard let self, var active = self.graphWheelQueue, active.id == queue.id else { return }
                guard succeeded, active.operation == self.operationRequestID, !self.isWorking,
                    let current = self.acceptedDocumentSource, self.admitsGraphWheel,
                    self.ownsCanvasProfile(queue.scope.lease),
                    self.graphWheelScope(current, lease: queue.scope.lease, usesHover: edit.usesHover) == queue.scope,
                    current.documentRevision == queue.revision || current.documentRevision == queue.revision + 1,
                    !active.pending.isEmpty
                else {
                    self.graphWheelQueue = nil
                    return
                }
                let next = active.pending.removeFirst()
                active.revision = current.documentRevision
                self.graphWheelQueue = active
                self.dispatchGraphWheel(next, snapshot: current)
            },
            { session in
                switch edit {
                case .selectionRadius(let delta): try await session.adjustSelectionRadius(by: delta, target: target)
                case .nodeRadius(let id, let delta):
                    try await session.adjustNodeRadius(id: id, by: delta, target: target)
                case .spacing(let factor):
                    try await session.scaleSelection(positionFactor: factor, radiusFactor: 1, target: target)
                }
            })
        if graphWheelQueue?.id == queue.id { graphWheelQueue?.operation = operationRequestID }
    }

    private(set) var canvasWheelZoomEnabled = false
    private var canvasWheelZoomEpoch = UUID()
    private(set) var canvasWheelZoom = MeshCameraWheelZoom()

    func setCanvasWheelZoomEnabled(_ enabled: Bool) {
        guard canvasWheelZoomEnabled != enabled, acceptedDocumentSource != nil else { return }
        canvasWheelZoomEnabled = enabled
        canvasWheelZoomEpoch = UUID()
    }

    func canvasPreviewWheelAction(
        lease: UUID?, camera: EditorPreviewCameraActions?
    ) -> @MainActor (CanvasWheelInput) -> Bool {
        guard canvasWheelZoomEnabled, let source = acceptedDocumentSource, let camera else {
            return { _ in false }
        }
        let target = CanvasAdjustmentTarget(snapshot: source)
        let profile = rigEdgeSelectionEpoch
        let tool = rotationInputContextID
        let add = addModeID
        let setting = canvasWheelZoomEpoch
        return { [weak self] input in
            guard let self, input.isSupported,
                input.modifiers.intersection([.shift, .command, .option, .control, .function]).isEmpty,
                self.admitsCanvasSelectionInput(epoch: profile, lease: lease),
                self.rotationInputContextID == tool, self.addModeID == add, self.canvasWheelZoomEpoch == setting,
                !self.isWorking, !self.isAddingNodes, !self.isMovingOrigin, !self.isSelectingRigEdges,
                self.originDrag == nil, !self.referenceColorInteractionActive, self.canvasGraphHover == nil,
                let current = self.acceptedDocumentSource, target.isCurrent(in: current),
                current.selectedIDs.isEmpty, current.selectedEdgeIDs.isEmpty
            else { return false }
            return camera.zoomFromCanvas(step: input.verticalDelta > 0 ? 1 : -1)
        }
    }

    func zoomPreviewFromCanvas(step: Int) {
        guard canMovePreviewCamera, canvasWheelZoomEnabled, step == 1 || step == -1 else { return }
        canvasWheelZoom.append(step: step)
    }

    private(set) var isWorking = false {
        didSet {
            if isWorking {
                canvasGraphHover = nil
                if !preservesCanvasPartStateHover { canvasPartStateHover = nil }
            }
            onEditingChanged?(isWorking)
        }
    }
    private(set) var previewState = MeshPreviewState<EditorPreviewOutput>() {
        didSet {
            if previewState.value == nil {
                previewCameraCommand = nil
                canvasWheelZoom = .init()
            }
        }
    }
    var mesh: IndexedMesh? { previewState.value?.mesh }
    var previewSourceHints: MeshSourceHints? {
        guard !previewState.isStale, !isWorking, !stopped else { return nil }
        return previewState.value?.sourceHints
    }
    private(set) var materialState = MeshPreviewState<MeshMaterialContent>()
    var materialContent: MeshMaterialContent? {
        materialRenderError == nil && !materialState.isStale ? materialState.value : nil
    }
    var bakedMesh: MeshWithBakedTextures? {
        guard case .baked(let value) = materialContent else { return nil }
        return value
    }
    var importedMaterials: ImportedMaterialRenderData? {
        guard case .imported(let value) = materialContent else { return nil }
        return value
    }
    var sourceBakedMesh: SourceBakedMesh? {
        guard case .sourceBaked(let value) = materialContent else { return nil }
        return value
    }
    var previewCompatibilityWarning: String? {
        let tree = snapshot?.componentTree
        let legacyDetails = tree.flatMap { tree -> Bool? in
            guard tree.failureDescription == nil else { return nil }
            return tree.rows.contains { $0.component.hasLegacySurfaceDetails }
        }
        return MaterialPreviewWarning.message(
            mesh?.warning ?? "",
            hasBakedMaterials: (bakedMesh != nil || sourceBakedMesh != nil)
                && renderedMaterialRevision == materialViewportRevision,
            hasImportedMaterials: (importedMaterials != nil || sourceBakedMesh != nil)
                && renderedMaterialRevision == materialViewportRevision,
            hasSourceBakedMaterials: sourceBakedMesh != nil
                && renderedMaterialRevision == materialViewportRevision,
            hasLegacySurfaceDetails: legacyDetails,
            hasRenderedSurfaceDetails: bakedMesh != nil && renderedMaterialRevision == materialViewportRevision,
            materialWarning: materialState.isStale ? nil : materialState.value?.preparationWarning)
    }
    private var renderedMaterialRevision: Int?

    func materialsRendered(revision: Int) {
        guard materialContent != nil, revision == materialViewportRevision else { return }
        renderedMaterialRevision = revision
    }

    func materialsFailed(_ cause: String, revision: Int) {
        guard materialContent != nil, revision == materialViewportRevision else { return }
        renderedMaterialRevision = nil
        materialRenderError = cause
    }

    var isBakingMaterials: Bool { materialState.isGenerating }
    var isUpdatingMaterials: Bool {
        isBakingMaterials || (materialContent != nil && renderedMaterialRevision != materialViewportRevision)
    }
    var materialRenderError: String?
    var materialIssue: String? { materialRenderError ?? materialState.errorMessage }
    var previewRevision: Int { previewState.revision }
    var materialViewportRevision: Int { previewState.revision + materialState.revision }
    var isGenerating: Bool { previewState.isGenerating }
    var errorMessage: String?
    var renderError: String? {
        didSet { if renderError != nil { previewCameraCommand = nil } }
    }
    var bounds = CanvasBounds(nodes: []) {
        didSet {
            if canvasPartStateHover != nil,
                CanvasProjection(bounds: oldValue, plane: plane, width: canvasWidth, height: canvasHeight)
                    != currentCanvasProjection
            {
                canvasPartStateHover = nil
            }
            if let canvas = referenceColorCanvas {
                updatePrecisionCanvasIdentity(
                    projection: CanvasProjection(
                        bounds: bounds, plane: plane,
                        width: canvas.identity.width, height: canvas.identity.height), width: canvas.identity.width,
                    height: canvas.identity.height)
                setReferenceColorCanvasContext(
                    projection: CanvasProjection(
                        bounds: bounds, plane: plane,
                        width: canvas.identity.width, height: canvas.identity.height),
                    width: canvas.identity.width, height: canvas.identity.height)
            }
        }
    }
    private var precisionLayoutEpoch = UUID()
    private var precisionCanvasIdentity: ReferenceColorCanvasIdentity?
    private var rotationInputContextID = UUID()
    private(set) var canvasProfiles = CanvasProfileWorkspace()
    var plane: EditingPlane {
        get { canvasProfiles.activePlane }
        set {
            guard newValue != plane else { return }
            canvasProfiles.activate(newValue)
            resetCanvasProfileContext(
                clearGeometry: canvasGeometryUsesProfileLease,
                transferAdd: canvasProfiles.isDualProfile && !isWorking && addPlacementRequestID == nil)
        }
    }

    func setDualCanvasProfile(_ enabled: Bool) {
        guard enabled != canvasProfiles.isDualProfile else { return }
        canvasProfiles.setDualProfile(enabled)
        resetCanvasProfileContext(clearGeometry: true)
    }

    var canSwitchSelectedCanvasProfile: Bool {
        guard canvasProfiles.isDualProfile, !stopped, !isWorking, !isAddingNodes, !isMovingOrigin, let snapshot else {
            return false
        }
        return !snapshot.selectedIDs.isEmpty || !snapshot.selectedEdgeIDs.isEmpty
    }

    func focusCanvasAction(
        fileIdentity: UUID? = nil, ownsWindow: @escaping @MainActor () -> Bool = { true },
        _ focus: @escaping @MainActor (CanvasProfileFocusTarget) -> Bool
    ) -> (@MainActor () -> Bool)? {
        guard canSave, !referenceColorInteractionActive, originDrag == nil, let source = acceptedDocumentSource,
            case .success(let accepted) = recoveryLoadResult, accepted.fileIdentity == fileIdentity, ownsWindow()
        else { return nil }
        let target = CanvasProfileFocusTarget(documentIdentity: source.documentIdentity, lease: canvasProfiles.lease)
        let tool = rotationInputContextID
        let add = addModeID
        let interaction = referenceColorInteractionEpoch
        return { [weak self] in
            guard let self, ownsWindow(), self.canSave,
                self.acceptedDocumentSource?.documentIdentity == target.documentIdentity,
                self.ownsCanvasProfile(target.lease), self.rotationInputContextID == tool, self.addModeID == add,
                self.referenceColorInteractionEpoch == interaction, !self.referenceColorInteractionActive,
                self.originDrag == nil
            else { return false }
            return focus(target)
        }
    }

    func switchSelectedCanvasProfile(expectedLease: UUID? = nil) -> UUID? {
        guard canSwitchSelectedCanvasProfile, ownsCanvasProfile(expectedLease) else { return nil }
        plane = plane == .front ? .side : .front
        return canvasProfiles.lease
    }

    func activateCanvasCompanion(plane: EditingPlane, expectedLease: UUID) -> UUID? {
        guard canvasProfiles.isDualProfile, plane != self.plane, ownsCanvasProfile(expectedLease) else { return nil }
        self.plane = plane
        canvasProfiles.markActivationClick()
        return canvasProfiles.lease
    }

    func admitsCanvasPrimaryPress(clickCount: Int, lease: UUID?) -> Bool {
        guard ownsCanvasProfile(lease) else { return false }
        guard let lease else { return true }
        return canvasProfiles.admitsPrimaryPress(clickCount: clickCount, lease: lease)
    }

    func ownsCanvasProfile(_ lease: UUID?) -> Bool {
        !stopped && (lease.map(canvasProfiles.owns) ?? true)
    }

    func releaseCanvasProfile(lease: UUID?) {
        guard ownsCanvasProfile(lease) else { return }
        if lease != nil { canvasProfiles.retireLease() }
        resetCanvasProfileContext(clearGeometry: true)
    }

    private(set) var canvasProfileMotion: CanvasProfileMotion?

    func beginCanvasProfileMotion(token: UUID, lease: UUID?) {
        guard canvasProfiles.isDualProfile, let lease, ownsCanvasProfile(lease), let snapshot else { return }
        canvasProfileMotion = CanvasProfileMotion(snapshot: snapshot, lease: lease, token: token)
    }

    func updateCanvasProfileMotion(_ payload: CanvasProfileMotion.Payload, token: UUID, lease: UUID?) {
        guard let lease, ownsCanvasProfile(lease), let snapshot, var motion = canvasProfileMotion,
            motion.update(payload, lease: lease, token: token, snapshot: snapshot)
        else { return }
        canvasProfileMotion = motion
    }

    func clearCanvasProfileMotion(token: UUID? = nil, lease: UUID?) {
        guard let lease, ownsCanvasProfile(lease), let motion = canvasProfileMotion, motion.lease == lease,
            token == nil || motion.token == token
        else { return }
        canvasProfileMotion = nil
    }

    private func resetCanvasProfileContext(clearGeometry: Bool, transferAdd: Bool = false) {
        rigEdgeSelectionEpoch = UUID()
        canvasProfileMotion = nil
        rotationInputContextID = UUID()
        precisionLayoutEpoch = UUID()
        precisionCanvasIdentity = nil
        clearReferenceColorCanvasContext()
        setReferenceColorInteractionActive(false)
        if transferAdd && isAddingNodes {
            addPlacement.suspendProjectionForProfileChange()
            addModeID = UUID()
        } else {
            cancelAddMode()
        }
        cancelOriginDrag()
        if clearGeometry {
            canvasWidth = 0
            setCanvasHeight(0)
        }
        clearCanvasHover()
    }

    private(set) var isMovingOrigin = false {
        didSet {
            if isMovingOrigin != oldValue {
                rotationInputContextID = UUID()
                cancelReferenceColorCommit()
            }
            if isMovingOrigin { clearCanvasHover() }
        }
    }
    private(set) var originDragPosition: NodePosition?
    private var originDrag: OriginDrag?
    private var originDragToken: UUID?
    var isWireframe = false
    var showsPreviewColor = true
    var automaticallyOrbitsPreview = false
    var isPreviewAutomaticallyOrbiting: Bool { automaticallyOrbitsPreview && canMovePreviewCamera }
    var cameraReset = 0
    private(set) var previewCameraCommand: MeshCameraCommand?
    var canMovePreviewCamera: Bool { !stopped && mesh != nil && renderError == nil }
    private(set) var referenceImage: CGImage?
    private(set) var referenceImageError: String?
    private(set) var isLoadingReferenceImage = false
    var showsReferenceImage = true {
        didSet {
            if showsReferenceImage != oldValue {
                invalidateReferenceColors()
                if showsReferenceImage { scheduleReferenceColors() }
            }
        }
    }
    var referenceImageOpacity = 0.5
    var hasReferenceImage: Bool { snapshot?.document.hasReferenceImage == true }
    var referenceImageForComposition: CGImage? {
        guard hasReferenceImage, !isLoadingReferenceImage, referenceImageError == nil else { return nil }
        return referenceImage
    }
    var onDocumentChanged: ((Data) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    private var animationValue: EditorAnimationSnapshot?
    private var animationRequestID = UUID()
    private(set) var animationQuery: Task<Void, Never>?
    private(set) var isLoadingAnimations = false
    private struct AnimationQueryFailure {
        let documentIdentity: UUID
        let documentRevision: Int
        let cause: any Error
    }
    private var animationQueryFailure: AnimationQueryFailure?
    private let session = EditorSession()
    let authoringCatalog: EditorAnimationCatalogState
    private let exportService: DocumentExportFileService?
    private var exportTask: Task<EditorExportReceipt, any Error>?

    // A retained preview may belong to a previous load; recovery must preserve current-load provenance and errors.
    private struct RecoveryLoadIdentity {
        let documentIdentity: UUID
        let fileIdentity: UUID?
    }
    private var recoveryLoadResult: Result<RecoveryLoadIdentity, any Error>?
    private let materialPreparation: any ArchiveMaterialPreparing
    private(set) var materialGeneration: Task<Void, Never>?
    private let preview: any EditorPreviewServing
    private var previewScopeID = UUID()
    private(set) var previewCacheStatistics: MeshGenerationStatistics?
    private(set) var previewSourceIssue: MeshLoadingError?
    private static let previewLogger = Logger(
        subsystem: RuntimeBuildIdentity.current.loggingSubsystem(fallback: "org.dust3d.editor"),
        category: "PreviewCache")
    private let colorImages: any ColorImageServing
    private(set) var colorImagePreparation: Task<Void, Never>?
    private(set) var isPreparingColorImage = false
    private var colorImageRequestID = UUID()
    private var operationRequestID = UUID()
    private let referenceColorRaster: any ReferenceColorRasterServing
    private let referenceColorApplying: any ReferenceColorApplying
    private var referenceColorCanvas: (identity: ReferenceColorCanvasIdentity, projection: CanvasProjection)?
    private var preparedReferenceColors: PreparedReferenceColors?
    private var referenceColorPreparationID = UUID()
    private(set) var referenceColorPreparation: Task<Void, Never>?
    private(set) var isPreparingReferenceColors = false
    private(set) var referenceColorError: String?
    private(set) var referenceColorNotice: String?
    private(set) var referenceColorCommitTask: Task<Void, Never>?
    private var referenceColorApplyToken = UUID()
    private var referenceColorOperationID: UUID?
    private var referenceColorInteractionActive = false
    private var referenceColorInteractionEpoch = UUID()
    private let referenceImages: any ReferenceImageServing
    private var operation: Task<Void, Never>?
    // Lifecycle callers can await a captured request's cooperative completion.
    private(set) var generation: Task<Void, Never>?
    private var referenceGeneration: Task<Void, Never>?
    private var referenceRequestID = UUID()
    private var stopped = false

    init(
        colorImages: any ColorImageServing = ColorImageService(),
        referenceImages: any ReferenceImageServing = ReferenceImageService(),
        preview: any EditorPreviewServing = EditorPreviewService(),
        materialBaker: any ArchiveTextureBaking = ArchiveTextureBakingService(),
        importedMaterialLoader: any ArchiveImportedMaterialLoading = ArchiveImportedMaterialService(),
        sourceMaterialBaker: any ArchiveSourceTextureBaking = ArchiveSourceTextureBakingService(),
        exportService: DocumentExportFileService? = nil,
        animationCatalog: (any AnimationCatalogLoading)? = nil,
        addPlacements: any AddPlacementServing = AddPlacementService(),
        referenceColorRaster: any ReferenceColorRasterServing = ReferenceColorRasterService(),
        referenceColorApplying: any ReferenceColorApplying = ReferenceColorApplicationService()
    ) {
        self.referenceColorRaster = referenceColorRaster
        self.referenceColorApplying = referenceColorApplying
        self.addPlacements = addPlacements
        authoringCatalog = EditorAnimationCatalogState(service: animationCatalog)
        self.exportService = exportService
        self.colorImages = colorImages
        self.referenceImages = referenceImages
        self.preview = preview
        materialPreparation = ArchiveMaterialPreparationService(
            importedLoader: importedMaterialLoader, proceduralBaker: materialBaker, sourceBaker: sourceMaterialBaker)
    }

    var locks: Set<EditingConstraint> { snapshot?.locks ?? [] }
    var canSave: Bool { !isWorking && acceptedDocumentSource != nil }
    var canEditRigSettings: Bool { canSave }

    private var acceptedDocumentSource: EditorSnapshot? {
        guard !stopped, case .success(let accepted) = recoveryLoadResult,
            let snapshot, snapshot.documentIdentity == accepted.documentIdentity
        else { return nil }
        return snapshot
    }

    var referenceCompositionTarget: ReferenceCompositionTarget? {
        guard canSave, let source = acceptedDocumentSource else { return nil }
        return ReferenceCompositionTarget(snapshot: source)
    }

    func getStartedAdmission(fileIdentity: UUID) -> (@MainActor () -> Bool)? {
        guard let source = getStartedSource(fileIdentity: fileIdentity) else { return nil }
        let target = CanvasAdjustmentTarget(snapshot: source)
        let tool = rotationInputContextID
        let add = addModeID
        let interaction = referenceColorInteractionEpoch
        return { [weak self] in
            guard let self, let current = self.getStartedSource(fileIdentity: fileIdentity) else { return false }
            return target.isCurrent(in: current) && self.rotationInputContextID == tool
                && self.addModeID == add && self.referenceColorInteractionEpoch == interaction
        }
    }

    private func getStartedSource(fileIdentity: UUID) -> EditorSnapshot? {
        guard !isWorking, !isAddingNodes, !isMovingOrigin, !referenceColorInteractionActive,
            let source = acceptedDocumentSource, case .success(let accepted) = recoveryLoadResult,
            accepted.fileIdentity == fileIdentity, source.nodes.isEmpty, source.parts.isEmpty,
            !source.document.hasReferenceImage
        else { return nil }
        return source
    }

    var animationSnapshot: EditorAnimationSnapshot? {
        guard let source = acceptedDocumentSource, let value = animationValue,
            value.editor.documentIdentity == source.documentIdentity,
            value.editor.documentRevision == source.documentRevision
        else { return nil }
        return value
    }

    var animationQueryIssue: (any Error)? {
        guard let failure = animationQueryFailure, let source = acceptedDocumentSource,
            source.documentIdentity == failure.documentIdentity,
            source.documentRevision == failure.documentRevision
        else { return nil }
        return failure.cause
    }

    var canManageAnimations: Bool {
        guard !isWorking, !isLoadingAnimations, animationQueryIssue == nil,
            let value = animationSnapshot, value.list.issue == nil
        else { return false }
        return true
    }

    func refreshAnimations() { requestAnimations { try await $0.animationSnapshot() } }

    func selectAnimation(_ id: String?) {
        requestAnimations { try await $0.selectAnimation(id) }
    }

    func createAnimation(name: String, type: String) {
        performAnimationMutation { try await $0.createAnimation(name: name, type: type) }
    }

    func createAnimation(
        name: String, type: String, parameters: [DocumentAnimationParameter], target: AnimationCreationTarget,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        performAnimationMutation(completion: completion) {
            try await $0.createAnimation(name: name, type: type, parameters: parameters, target: target)
        }
    }

    func editAnimation(
        _ edits: [AnimationEdit], target: AnimationEditTarget, completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        performAnimationMutation(completion: completion) { try await $0.editAnimation(edits, target: target) }
    }

    func editAnimation(
        _ edit: AnimationEdit, target: AnimationEditTarget, completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        performAnimationMutation(completion: completion) { try await $0.editAnimation(edit, target: target) }
    }

    func duplicateAnimation(
        target: AnimationEditTarget, name: String, completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        performAnimationMutation(completion: completion) { try await $0.duplicateAnimation(target: target, name: name) }
    }

    private func performAnimationMutation(
        completion: (@MainActor (Bool) -> Void)? = nil,
        _ action: @escaping @Sendable (EditorSession) async throws -> EditorAnimationSnapshot
    ) {
        guard canManageAnimations else {
            completion?(false)
            return
        }
        let refreshAfterPublication: @MainActor (Bool) -> Void = { [weak self] succeeded in
            if succeeded { self?.refreshAnimations() }
            completion?(succeeded)
        }
        perform(completion: refreshAfterPublication) { session in
            let result = try await action(session)
            return result.editor
        }
    }

    private func requestAnimations(
        _ action: @escaping @Sendable (EditorSession) async throws -> EditorAnimationSnapshot
    ) {
        guard !isWorking, let source = acceptedDocumentSource else { return }
        let sourceIdentity = source.documentIdentity
        let sourceRevision = source.documentRevision
        let requestID = UUID()
        animationRequestID = requestID
        animationQuery?.cancel()
        animationQueryFailure = nil
        isLoadingAnimations = true
        animationQuery = Task { [weak self, session] in
            defer {
                if let self, self.animationRequestID == requestID { self.isLoadingAnimations = false }
            }
            do {
                let result = try await action(session)
                guard !Task.isCancelled, let self, self.animationRequestID == requestID, !self.isWorking,
                    let current = self.acceptedDocumentSource,
                    current.documentIdentity == result.editor.documentIdentity,
                    current.documentRevision == result.editor.documentRevision
                else { return }
                self.animationValue = result
            } catch {
                guard !Task.isCancelled, let self, self.animationRequestID == requestID,
                    let current = self.acceptedDocumentSource,
                    current.documentIdentity == sourceIdentity, current.documentRevision == sourceRevision
                else { return }
                self.animationQueryFailure = .init(
                    documentIdentity: sourceIdentity, documentRevision: sourceRevision, cause: error)
            }
        }
    }

    private func cancelAnimationQuery() {
        animationRequestID = UUID()
        animationQuery?.cancel()
        animationQuery = nil
        animationValue = nil
        animationQueryFailure = nil
        isLoadingAnimations = false
    }

    var canExport: Bool {
        guard exportService != nil, canSave,
            case .success(let accepted) = recoveryLoadResult,
            snapshot?.documentIdentity == accepted.documentIdentity
        else { return false }
        return true
    }

    /// Export one accepted snapshot without changing save state, history, preview or source bytes.
    /// Production scene commands must inject a reviewed native encoder and supply their source URL.
    func exportDocument(
        format: DocumentExportFormat, to destination: URL, sourceURL: URL?, capturedTarget: EditorExportTarget? = nil
    ) async throws -> EditorExportReceipt {
        try Task.checkCancellation()
        guard let exportService else { throw EditorExportWorkflowError.unavailable }
        guard !isWorking, !stopped, let recoveryLoadResult else { throw EditorExportWorkflowError.notReady }
        let accepted = try recoveryLoadResult.get()
        guard let snapshot, snapshot.documentIdentity == accepted.documentIdentity else {
            throw EditorExportWorkflowError.notReady
        }
        let target = capturedTarget ?? EditorExportTarget(snapshot: snapshot)
        cancelColorImagePreparation()
        cancelOriginDrag()
        let requestID = UUID()
        operationRequestID = requestID
        isWorking = true
        let task = Task { [session] in
            let output = try await exportService.export(
                snapshot.document, format: format, to: destination, sourceURL: sourceURL,
                validateSnapshot: { try await session.validateExport(target) },
                publish: { commit in try await session.publishExport(target, publication: commit) })
            return EditorExportReceipt(
                documentIdentity: snapshot.documentIdentity, documentRevision: snapshot.documentRevision,
                destination: destination, format: format, byteCount: output.bytes.count, warning: output.warning)
        }
        exportTask = task
        defer {
            if operationRequestID == requestID {
                exportTask = nil
                isWorking = false
            }
        }
        do {
            let receipt = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            if operationRequestID == requestID { errorMessage = nil }
            return receipt
        } catch {
            if operationRequestID == requestID, !stopped, !(error is CancellationError) {
                errorMessage = Self.message(error)
            }
            throw error
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
    }

    func setRigType(_ type: DocumentRigType) {
        guard canEditRigSettings else { return }
        perform { try await $0.apply([.setRigType(type)]) }
    }

    func setHeadHasEyelids(_ enabled: Bool) {
        guard canEditRigSettings else { return }
        perform { try await $0.apply([.setHeadHasEyelids(enabled)]) }
    }

    func recoverySnapshot(documentID: UUID) throws -> EditorRecoverySnapshot {
        guard !stopped else { throw EditorRecoveryCopyError.stopped }
        guard !isWorking else { throw EditorRecoveryCopyError.editInProgress }
        guard let recoveryLoadResult else { throw EditorRecoveryCopyError.notLoaded }
        let accepted = try recoveryLoadResult.get()
        if let fileIdentity = accepted.fileIdentity, fileIdentity != documentID {
            throw EditorRecoveryCopyError.identityMismatch
        }
        guard let snapshot, snapshot.documentIdentity == accepted.documentIdentity else {
            throw EditorRecoveryCopyError.notLoaded
        }
        return .init(documentID: documentID, revision: snapshot.documentRevision, document: snapshot.document)
    }
    var canUndo: Bool { canSave && snapshot?.canUndo == true }
    var canRedo: Bool { canSave && snapshot?.canRedo == true }

    /// Scene callers supply their FileDocument identity so recovery cannot relabel retained preview state.
    func load(data: Data, fileIdentity: UUID? = nil) async {
        graphComponentRevealLookup = nil
        canvasAxisLockQueue = nil
        changeRigEdgeSelection(false)
        changeComponentBrowseGroup(nil, reset: true)
        pendingComponentDrag = nil
        invalidateReferenceColors()
        referenceColorApplyToken = UUID()
        referenceColorOperationID = nil
        pendingWholePartPick = nil
        isSelectingGraph = false
        cancelAddMode(refit: false)
        changeAddPlacementDestination(.selection)
        cancelAnimationQuery()
        cancelExport()
        cancelColorImagePreparation()
        graphWheelQueue = nil
        operation?.cancel()
        let requestID = UUID()
        operationRequestID = requestID
        cancelOriginDrag()
        stopped = false
        isWorking = true
        recoveryLoadResult = nil
        qtXMLFilePasteRequest = nil
        defer { if operationRequestID == requestID { isWorking = false } }
        do {
            let next = try await session.open(data: data)
            guard !Task.isCancelled, !stopped, operationRequestID == requestID else { return }
            snapshot = next
            recoveryLoadResult = .success(.init(documentIdentity: next.documentIdentity, fileIdentity: fileIdentity))
            referenceImage = nil
            fit()
            clearPreview()
            generate(next)
            refreshReferenceImage(next, forceFit: true)
        } catch {
            if !Task.isCancelled, operationRequestID == requestID {
                recoveryLoadResult = .failure(error)
                errorMessage = Self.message(error)
            }
        }
    }

    func cancelColorImagePreparation() {
        colorImageRequestID = UUID()
        colorImagePreparation?.cancel()
        colorImagePreparation = nil
        isPreparingColorImage = false
    }

    private enum PreparedColorImage: Sendable {
        case imported(Data)
        case retained(String)
    }

    enum ComponentColorImageDestination: Sendable {
        case component(ComponentColorImageTarget)
        case graph(ComponentMeshSelectionTarget)

        func isCurrent(in snapshot: EditorSnapshot) -> Bool {
            switch self {
            case .component(let target): target.isCurrent(in: snapshot)
            case .graph(let target): !target.graphColorImageComponents(in: snapshot).isEmpty
            }
        }
    }

    func canEditComponentColorImage(_ destination: ComponentColorImageDestination) -> Bool {
        !isWorking && acceptedDocumentSource.map { destination.isCurrent(in: $0) } == true
    }

    func componentColorImageInspectionRequest(
        asset requestedAsset: DocumentColorImageAsset?, destination: ComponentColorImageDestination
    ) -> ComponentColorImageInspectionRequest? {
        guard !isWorking, let source = acceptedDocumentSource else { return nil }
        let components: [DocumentComponent]
        switch destination {
        case .component(let target):
            guard target.isCurrent(in: source), let component = source.selectedComponent else { return nil }
            components = [component]
        case .graph(let target):
            components = target.graphColorImageComponents(in: source)
            guard !components.isEmpty else { return nil }
        }
        let asset: DocumentColorImageAsset?
        if let requestedAsset {
            asset = source.colorImageAssets.first { $0 == requestedAsset }
        } else {
            guard let first = components.first,
                let identity = ComponentColorImagePresentation.assetIdentity(first.colorImage),
                components.dropFirst().allSatisfy({
                    ComponentColorImagePresentation.assetIdentity($0.colorImage) == identity
                })
            else { return nil }
            asset = source.colorImageAssets.first { $0.id == identity }
        }
        guard let asset, asset.canAssign else { return nil }
        return ComponentColorImageInspectionRequest(
            document: source.document, asset: asset, context: CanvasAdjustmentTarget(snapshot: source))
    }

    func canInspectComponentColorImage(_ request: ComponentColorImageInspectionRequest) -> Bool {
        guard !isWorking, let source = acceptedDocumentSource else { return false }
        return request.context.isCurrent(in: source)
    }

    func importComponentColorImage(url: URL, target: ComponentColorImageTarget) {
        importComponentColorImage(url: url, destination: .component(target))
    }

    func importComponentColorImage(url: URL, destination: ComponentColorImageDestination) {
        prepareComponentColorImage(destination: destination) { [colorImages] in
            .imported(try await colorImages.importImage(url: url))
        }
    }

    func assignComponentColorImage(_ asset: DocumentColorImageAsset, target: ComponentColorImageTarget) {
        assignComponentColorImage(asset, destination: .component(target))
    }

    func assignComponentColorImage(_ asset: DocumentColorImageAsset, destination: ComponentColorImageDestination) {
        guard let snapshot, canEditComponentColorImage(destination), let imageID = asset.imageID else { return }
        let document = snapshot.document
        prepareComponentColorImage(destination: destination) { [colorImages] in
            try await colorImages.validateRetainedImage(document: document, asset: asset)
            return .retained(imageID)
        }
    }

    func clearComponentColorImage(target: ComponentColorImageTarget) {
        clearComponentColorImage(destination: .component(target))
    }

    func clearComponentColorImage(destination: ComponentColorImageDestination) {
        guard canEditComponentColorImage(destination) else { return }
        perform { session in
            switch destination {
            case .component(let target): try await session.setComponentColorImage(imageID: nil, target: target)
            case .graph(let target): try await session.setComponentColorImages(imageID: nil, target: target)
            }
        }
    }

    private func prepareComponentColorImage(
        destination: ComponentColorImageDestination,
        prepare: @escaping @Sendable () async throws -> PreparedColorImage
    ) {
        guard canEditComponentColorImage(destination) else { return }
        cancelColorImagePreparation()
        let requestID = colorImageRequestID
        isPreparingColorImage = true
        errorMessage = nil
        colorImagePreparation = Task {
            defer {
                if colorImageRequestID == requestID {
                    isPreparingColorImage = false
                    colorImagePreparation = nil
                }
            }
            do {
                let prepared = try await prepare()
                guard !Task.isCancelled, !stopped, colorImageRequestID == requestID,
                    self.canEditComponentColorImage(destination)
                else { return }
                // End preparation before perform invalidates pending image requests.
                isPreparingColorImage = false
                colorImagePreparation = nil
                perform { session in
                    switch (prepared, destination) {
                    case (.imported(let png), .component(let target)):
                        try await session.importComponentColorImage(png: png, target: target)
                    case (.retained(let imageID), .component(let target)):
                        try await session.setComponentColorImage(imageID: imageID, target: target)
                    case (.imported(let png), .graph(let target)):
                        try await session.importComponentColorImages(png: png, target: target)
                    case (.retained(let imageID), .graph(let target)):
                        try await session.setComponentColorImages(imageID: imageID, target: target)
                    }
                }
            } catch {
                if !Task.isCancelled, colorImageRequestID == requestID, canEditComponentColorImage(destination) {
                    errorMessage = Self.message(error)
                }
            }
        }
    }

    func setMovingOrigin(_ enabled: Bool) {
        guard !enabled || !isSelectingRigEdges else { return }
        if enabled { cancelAddMode() }
        cancelOriginDrag()
        isMovingOrigin = enabled && canSave && snapshot?.origin != nil
    }

    func cancelOriginDrag(preservingMode: Bool = false) {
        if !preservingMode { isMovingOrigin = false }
        originDrag = nil
        originDragToken = nil
        originDragPosition = nil
    }

    func beginOriginDrag(token: UUID, projection: CanvasProjection) {
        guard isMovingOrigin, !isWorking, !stopped, let snapshot else { return }
        do {
            originDrag = try OriginDrag(snapshot: snapshot, projection: projection)
            originDragToken = token
            originDragPosition = nil
        } catch {
            cancelOriginDrag()
            errorMessage = Self.message(error)
        }
    }

    func updateOriginDrag(token: UUID, translation: CanvasPoint) {
        guard isMovingOrigin, !isWorking, !stopped, token == originDragToken,
            let snapshot, let baseline = originDrag
        else { return }
        do {
            guard baseline.isCurrent(in: snapshot) else {
                cancelOriginDrag()
                return
            }
            let position = baseline.position(by: translation)
            guard [translation.x, translation.y, position.x, position.y, position.z].allSatisfy(\.isFinite),
                [position.x, position.y, position.z].allSatisfy({ abs($0) <= 1_000_000 })
            else { throw DocumentError.invalidOrigin }
            originDragPosition = position
        } catch {
            cancelOriginDrag()
            errorMessage = Self.message(error)
        }
    }

    func finishOriginDrag(token: UUID, translation: CanvasPoint) {
        guard isMovingOrigin, token == originDragToken, let baseline = originDrag else { return }
        perform { try await $0.commitOriginDrag(baseline, translation: translation) }
    }

    func cancelOriginDrag(token: UUID) {
        guard token == originDragToken else { return }
        cancelOriginDrag()
    }

    func endOriginClick(token: UUID) {
        guard token == originDragToken else { return }
        originDrag = nil
        originDragToken = nil
        originDragPosition = nil
    }

    private struct CanvasAxisLockScope: Equatable {
        let documentIdentity: UUID
        let documentRevision: Int
        let selectionRevision: Int
        let profileLease: UUID?
        let toolEpoch: UUID
        let addEpoch: UUID
        let interactionEpoch: UUID
    }

    private struct CanvasAxisLockQueue {
        let id = UUID()
        let scope: CanvasAxisLockScope
        let firstConstraintRevision: Int
        var operationID: UUID?
        var pending: [EditingConstraint] = []
    }

    @ObservationIgnored private var canvasAxisLockQueue: CanvasAxisLockQueue?

    func canvasAxisLockKeyHandler(profileLease: UUID?) -> @MainActor (CanvasPrecisionKeyInput) -> Bool {
        guard let snapshot = acceptedDocumentSource else { return { _ in false } }
        let scope = canvasAxisLockScope(snapshot: snapshot, profileLease: profileLease)
        let capturedRevision = snapshot.constraintRevision
        return { [weak self] input in
            guard let self, let constraint = input.axisLockConstraint,
                let current = admittedCanvasAxisLockSource(scope)
            else { return false }
            if let queue = canvasAxisLockQueue {
                guard queue.scope == scope, queue.operationID == operationRequestID,
                    (queue.firstConstraintRevision...current.constraintRevision).contains(capturedRevision)
                else { return false }
                if !input.isRepeat, queue.pending.count < 32 {
                    canvasAxisLockQueue?.pending.append(constraint)
                }
                return true
            }
            guard !isWorking, capturedRevision == current.constraintRevision else { return false }
            if !input.isRepeat {
                canvasAxisLockQueue = CanvasAxisLockQueue(scope: scope, firstConstraintRevision: capturedRevision)
                dispatchCanvasAxisLock(constraint, snapshot: current)
            }
            return true
        }
    }

    private func canvasAxisLockScope(snapshot: EditorSnapshot, profileLease: UUID?) -> CanvasAxisLockScope {
        CanvasAxisLockScope(
            documentIdentity: snapshot.documentIdentity, documentRevision: snapshot.documentRevision,
            selectionRevision: snapshot.selectionRevision, profileLease: profileLease,
            toolEpoch: rotationInputContextID,
            addEpoch: addModeID, interactionEpoch: referenceColorInteractionEpoch)
    }

    private func admittedCanvasAxisLockSource(_ scope: CanvasAxisLockScope) -> EditorSnapshot? {
        guard ownsCanvasProfile(scope.profileLease), !referenceColorInteractionActive,
            !isSelectingRigEdges, !isAddingNodes, !isMovingOrigin, canvasProfileMotion == nil,
            let current = acceptedDocumentSource,
            canvasAxisLockScope(snapshot: current, profileLease: scope.profileLease) == scope
        else { return nil }
        return current
    }

    private func dispatchCanvasAxisLock(_ constraint: EditingConstraint, snapshot: EditorSnapshot) {
        guard let queue = canvasAxisLockQueue else { return }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        let revision = snapshot.constraintRevision
        perform(
            commits: false,
            completion: { [weak self] succeeded in
                guard let self, var currentQueue = canvasAxisLockQueue, currentQueue.id == queue.id else { return }
                guard succeeded, currentQueue.operationID == operationRequestID, !isWorking,
                    let current = admittedCanvasAxisLockSource(queue.scope),
                    current.constraintRevision == revision + 1, !currentQueue.pending.isEmpty
                else {
                    canvasAxisLockQueue = nil
                    return
                }
                let next = currentQueue.pending.removeFirst()
                canvasAxisLockQueue = currentQueue
                dispatchCanvasAxisLock(next, snapshot: current)
            },
            { try await $0.toggleCanvasAxisLock(constraint, target: target) })
        if canvasAxisLockQueue?.id == queue.id { canvasAxisLockQueue?.operationID = operationRequestID }
    }

    func setLock(_ constraint: EditingConstraint, isLocked: Bool) {
        perform(commits: false) { try await $0.setLock(constraint, isLocked: isLocked) }
    }

    func select(_ id: String?) {
        guard !isSelectingRigEdges || id == nil else { return }
        perform(commits: false, selectionOnly: true) { try await $0.select(id) }
    }

    func select(_ ids: Set<String>) {
        guard !isSelectingRigEdges || ids.isEmpty else { return }
        perform(commits: false, selectionOnly: true) { try await $0.select(ids) }
    }
    func selectEdge(_ id: String?) { perform(commits: false, selectionOnly: true) { try await $0.selectEdge(id) } }
    func selectGraph(nodes: Set<String>, edges: Set<String>, mode: GraphSelectionMode = .replace) {
        guard !isSelectingRigEdges || nodes.isEmpty else { return }
        perform(commits: false, selectionOnly: true) { session in
            switch mode {
            case .replace: try await session.selectGraph(nodes: nodes, edges: edges)
            case .add: try await session.addToSelection(nodes: nodes, edges: edges)
            case .toggle: try await session.toggleGraphSelection(nodes: nodes, edges: edges)
            case .subtract: try await session.removeFromSelection(nodes: nodes, edges: edges)
            }
        }
    }
    func edgeSidebarSelectionAction(
        _ id: String, context: PartGraphSelectionContext?
    ) -> @MainActor (GraphSelectionMode) -> Void {
        { [weak self] mode in
            guard let self, self.canPickGraph, let context, let snapshot = self.snapshot,
                context.isCurrent(in: snapshot), snapshot.edges.contains(where: { $0.id.utf8.elementsEqual(id.utf8) })
            else { return }
            if case .subtract = mode,
                !snapshot.selectedEdgeIDs.contains(where: { $0.utf8.elementsEqual(id.utf8) })
            {
                return
            }
            self.selectGraph(nodes: [], edges: [id], mode: mode)
        }
    }

    var edgeSidebarSelectAllTarget: EdgeSidebarSelectAllTarget? {
        guard let snapshot, !snapshot.edges.isEmpty else { return nil }
        let eligible = isSelectingRigEdges ? rigEdgePickCandidates(in: snapshot, mode: .replace) : snapshot.edges
        return .init(
            ids: Set(eligible.map(\.id)), context: CanvasAdjustmentTarget(snapshot: snapshot),
            rigModeEpoch: rigEdgeSelectionEpoch)
    }

    func canSelectAllSidebarEdges(_ target: EdgeSidebarSelectAllTarget) -> Bool {
        guard canSave, let snapshot, !target.ids.isEmpty else { return false }
        return rigEdgeSelectionEpoch == target.rigModeEpoch && target.context.isCurrent(in: snapshot)
    }

    func selectAllSidebarEdges(_ target: EdgeSidebarSelectAllTarget) {
        guard canSelectAllSidebarEdges(target) else { return }
        let (ids, context) = (target.ids, target.context)
        perform(commits: false, selectionOnly: true) { try await $0.selectEdges(ids, target: context) }
    }

    func selectEdges(_ ids: Set<String>) {
        perform(commits: false, selectionOnly: true) { try await $0.selectEdges(ids) }
    }
    func toggleEdgeSelection(_ id: String) {
        perform(commits: false, selectionOnly: true) { try await $0.toggleEdgeSelection(id) }
    }
    func pickEdge(at point: CanvasPoint, projection: CanvasProjection, mode: GraphSelectionMode) {
        guard !isWorking, let snapshot else { return }
        let edges = isSelectingRigEdges ? rigEdgePickCandidates(in: snapshot, mode: mode) : snapshot.edges
        if let edge = projection.edgeID(near: point, nodes: snapshot.nodes, edges: edges) {
            selectGraph(nodes: [], edges: [edge], mode: mode)
        } else if mode == .replace {
            selectGraph(nodes: [], edges: [])
        }
    }
    func selectMarquee(_ rectangle: CanvasSelectionRectangle, projection: CanvasProjection, mode: GraphSelectionMode) {
        guard !isWorking, let snapshot else { return }
        let edges = isSelectingRigEdges ? rigEdgePickCandidates(in: snapshot, mode: mode) : snapshot.edges
        selectGraph(
            nodes: isSelectingRigEdges ? [] : projection.nodeIDs(in: rectangle, nodes: snapshot.nodes),
            edges: projection.edgeIDs(
                in: rectangle, nodes: snapshot.nodes, edges: edges, selectedEdgeIDs: snapshot.selectedEdgeIDs),
            mode: mode)
    }

    private func rigEdgePickCandidates(in snapshot: EditorSnapshot, mode: GraphSelectionMode) -> [DocumentEdge] {
        let editable = EdgeBoneAssignmentEligibility.edgeIDs(
            nodes: snapshot.nodes, edges: snapshot.edges, parts: snapshot.parts)
        return snapshot.edges.filter {
            editable.contains(Data($0.id.utf8))
                || ((mode == .subtract || mode == .toggle) && snapshot.selectedEdgeIDs.contains($0.id))
        }
    }

    func canDeleteComponentSubtrees(_ target: ComponentDeletionTarget) -> Bool {
        guard !isWorking, !stopped, let snapshot else { return false }
        return target.isCurrent(in: snapshot)
    }
    func componentDeletionAction(_ target: ComponentDeletionTarget) -> @MainActor () -> Void {
        guard canDeleteComponentSubtrees(target) else { return {} }
        return { [weak self] in
            guard let self, self.canDeleteComponentSubtrees(target) else { return }
            self.perform(acceptCommittedCancellation: true) { try await $0.deleteComponentSubtrees(target: target) }
        }
    }

    func selectComponent(_ id: String?) { perform(commits: false) { try await $0.selectComponent(id) } }
    func canEditComponentMeshSettings(_ target: ComponentMeshSelectionTarget) -> Bool {
        !stopped && !isWorking && target.count > (target.isGraphSelection ? 0 : 1)
            && snapshot.map { target.isCurrent(in: $0) } == true
    }
    func componentMeshAction(_ edit: ComponentMeshEdit, target: ComponentMeshSelectionTarget) -> @MainActor () -> Void {
        guard canEditComponentMeshSettings(target) else { return {} }
        return { [weak self] in
            guard let self, self.canEditComponentMeshSettings(target) else { return }
            self.perform(acceptCommittedCancellation: true) {
                try await $0.editSelectedComponentMeshSettings(edit, target: target)
            }
        }
    }
    func componentMeshSmoothingAction(_ text: String, target: ComponentMeshSelectionTarget) -> @MainActor () -> Void {
        guard let value = ComponentMeshSmoothingInput.value(text) else { return {} }
        return componentMeshAction(.smoothCutoffDegrees(value), target: target)
    }
    private var componentBrowseGroupID: String?
    private(set) var componentBrowseEpoch = UUID()

    var componentGroupBrowse: ComponentGroupBrowse? {
        guard let id = componentBrowseGroupID, let snapshot else { return nil }
        return ComponentGroupBrowse(tree: snapshot.componentTree, groupID: id)
    }

    var canBrowseComponents: Bool { !isWorking && acceptedDocumentSource != nil }

    func componentBrowseAction(_ groupID: String?, snapshot: EditorSnapshot) -> @MainActor () -> Void {
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        let source = PartGraphSelectionContext(snapshot: snapshot)
        let epoch = componentBrowseEpoch
        return { [weak self] in
            guard let self, self.canBrowseComponents, self.componentBrowseEpoch == epoch,
                let current = self.acceptedDocumentSource, target.isCurrent(in: current)
            else { return }
            guard let groupID else {
                self.changeComponentBrowseGroup(nil)
                return
            }
            guard let group = ComponentGroupBrowse(tree: current.componentTree, groupID: groupID) else { return }
            let retained = current.selectedComponentIDs.filter(group.contains)
            if retained == current.selectedComponentIDs {
                self.changeComponentBrowseGroup(groupID)
                return
            }
            self.perform(
                commits: false,
                completion: { [weak self] succeeded in
                    guard succeeded, let self, self.componentBrowseEpoch == epoch,
                        let next = self.acceptedDocumentSource, source.isCurrent(in: next)
                    else { return }
                    self.changeComponentBrowseGroup(groupID)
                },
                { try await $0.selectComponents(retained, target: target) })
        }
    }

    private func changeComponentBrowseGroup(_ groupID: String?, reset: Bool = false) {
        let changed = componentBrowseGroupID.map { Data($0.utf8) } != groupID.map { Data($0.utf8) }
        guard reset || changed else { return }
        componentBrowseGroupID = groupID
        componentBrowseEpoch = UUID()
        pendingComponentDrag = nil
        if changed, addPlacementDestination == .selection {
            workingGroupRevision = UUID()
            if addPlacement.anchorID == nil { cancelAddMode() }
        }
    }

    private func reconcileComponentBrowse(previous: EditorSnapshot?) {
        guard let current = snapshot, previous?.documentIdentity == current.documentIdentity,
            let group = componentGroupBrowse, current.selectedComponentIDs.allSatisfy(group.contains)
        else {
            changeComponentBrowseGroup(nil)
            return
        }
        if let hint = current.componentRevealHint, previous?.componentRevealHint != hint,
            !group.contains(hint.componentID)
        {
            changeComponentBrowseGroup(nil)
        }
    }

    func admitsComponentSidebarInput(context: PartGraphSelectionContext, scopeEpoch: UUID) -> Bool {
        !isWorking && componentBrowseEpoch == scopeEpoch
            && acceptedDocumentSource.map { context.isCurrent(in: $0) } == true
    }

    func selectBrowsedComponents(_ ids: Set<String>, scopeEpoch: UUID) {
        guard canBrowseComponents, componentBrowseEpoch == scopeEpoch,
            componentGroupBrowse.map({ ids.allSatisfy($0.contains) }) != false
        else { return }
        selectComponents(ids)
    }

    func canSelectAllVisibleComponents(_ target: ComponentSidebarSelectAllTarget) -> Bool {
        guard canSave, let snapshot, !target.ids.isEmpty,
            target.scopeEpoch.map({ $0 == componentBrowseEpoch }) ?? (componentBrowseGroupID == nil),
            componentGroupBrowse.map({ target.ids.allSatisfy($0.contains) }) != false
        else { return false }
        return target.context.isCurrent(in: snapshot)
    }

    func selectAllVisibleComponents(_ target: ComponentSidebarSelectAllTarget) {
        guard canSelectAllVisibleComponents(target) else { return }
        perform(commits: false) { try await $0.selectComponents(target.ids, target: target.context) }
    }

    func selectComponents(_ ids: Set<String>) { perform(commits: false) { try await $0.selectComponents(ids) } }
    func selectOnlyComponent(_ id: String) {
        guard snapshot?.selectedComponentIDs.contains(id) == true else { return }
        selectComponent(id)
    }
    func clearComponentSelection() { selectComponents([]) }
    func canAssignComponentPartRole(_ role: PartTarget) -> Bool {
        !isWorking && !stopped && (try? snapshot?.componentPartRolePlan(role)) != nil
    }

    /// Capture once at menu/inspector construction; an unavailable action never acquires a later selection.
    func componentPartRoleAction(_ role: PartTarget) -> @MainActor () -> Void {
        guard canAssignComponentPartRole(role), let snapshot else { return {} }
        let target = ComponentPartRoleTarget(snapshot: snapshot)
        return { [weak self] in
            guard let self, let current = self.snapshot, target.isCurrent(in: current),
                self.canAssignComponentPartRole(role)
            else { return }
            self.perform(acceptCommittedCancellation: true) {
                try await $0.setSelectedComponentPartRole(role, target: target)
            }
        }
    }

    var canGroupComponents: Bool { canSave && snapshot?.canGroupComponents == true }
    // Compatibility entry point for callers; all UI paths use the same captured batch eligibility.
    var canUngroupComponent: Bool {
        guard let snapshot else { return false }
        return canUngroupComponents(ComponentUngroupTarget(snapshot: snapshot))
    }
    func canUngroupComponents(_ target: ComponentUngroupTarget) -> Bool {
        !stopped && !isWorking && snapshot.map { target.isCurrent(in: $0) } == true
    }
    func componentUngroupAction(_ target: ComponentUngroupTarget) -> @MainActor () -> Void {
        guard canUngroupComponents(target) else { return {} }
        return { [weak self] in
            guard let self, self.canUngroupComponents(target) else { return }
            self.perform(acceptCommittedCancellation: true) { try await $0.ungroupComponents(target: target) }
        }
    }
    func groupSelectedComponents() {
        guard let snapshot else { return }
        componentGroupingAction(snapshot: snapshot, scopeEpoch: componentBrowseEpoch)()
    }

    func componentGroupingAction(snapshot: EditorSnapshot, scopeEpoch: UUID) -> @MainActor () -> Void {
        guard snapshot.canGroupComponents else { return {} }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        let ids = Set(snapshot.selectedComponentRows.map(\.id))
        return { [weak self] in
            guard let self, !self.isWorking, self.componentBrowseEpoch == scopeEpoch,
                let current = self.acceptedDocumentSource, target.isCurrent(in: current)
            else { return }
            self.perform(acceptCommittedCancellation: true) { try await $0.groupComponents(ids, target: target) }
        }
    }
    func ungroupSelectedComponent() {
        guard let snapshot else { return }
        componentUngroupAction(ComponentUngroupTarget(snapshot: snapshot))()
    }
    func reparentComponent(
        to parent: ComponentParent, target: ComponentReparentTarget,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        perform(completion: completion) { try await $0.reparentComponent(to: parent, target: target) }
    }
    func reparentComponents(
        to parent: ComponentParent, target: ComponentBatchReparentTarget,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard !stopped, !isWorking, let snapshot, target.isCurrent(in: snapshot),
            target.parentOptions().contains(where: { $0.id == parent })
        else {
            completion?(false)
            return
        }
        perform(acceptCommittedCancellation: true, completion: completion) {
            try await $0.reparentComponents(to: parent, target: target)
        }
    }
    @ObservationIgnored private var pendingComponentDrag: (token: UUID, target: ComponentPlacementTarget)?

    func beginComponentDrag(grabbedID: String) -> UUID? {
        pendingComponentDrag = nil
        guard canSave, let snapshot,
            let target = ComponentPlacementTarget(snapshot: snapshot, grabbedID: grabbedID)
        else { return nil }
        let token = UUID()
        pendingComponentDrag = (token, target)
        return token
    }

    func dropComponents(token: UUID, at placement: ComponentDropPlacement) -> Bool {
        guard let target = consumeComponentDrag(token) else { return false }
        return placeComponents(at: placement, target: target)
    }

    func dropComponents(token: UUID, in parent: ComponentParent) -> Bool {
        guard let target = consumeComponentDrag(token) else { return false }
        return placeComponents(at: .into(parentID: parent.componentID), target: target)
    }

    private func consumeComponentDrag(_ token: UUID) -> ComponentPlacementTarget? {
        guard let drag = pendingComponentDrag, drag.token == token else { return nil }
        pendingComponentDrag = nil
        guard canSave, let snapshot, drag.target.isCurrent(in: snapshot) else { return nil }
        return drag.target
    }

    @discardableResult
    func placeComponents(at placement: ComponentDropPlacement, target: ComponentPlacementTarget) -> Bool {
        guard canSave, let snapshot, target.canPlace(at: placement, in: snapshot) else { return false }
        perform(acceptCommittedCancellation: true) {
            try await $0.placeComponents(at: placement, target: target)
        }
        return true
    }
    func canReorderSidebarComponent(
        _ move: ComponentOrderMove, target: ComponentPlacementTarget, scopeEpoch: UUID
    ) -> Bool {
        guard canSave, scopeEpoch == componentBrowseEpoch, let snapshot,
            let placement = target.siblingPlacement(for: move, in: snapshot)
        else {
            return false
        }
        return target.canPlace(at: placement, in: snapshot)
    }

    @discardableResult
    func reorderSidebarComponent(
        _ move: ComponentOrderMove, target: ComponentPlacementTarget, scopeEpoch: UUID
    ) -> Bool {
        guard scopeEpoch == componentBrowseEpoch, let snapshot,
            let placement = target.siblingPlacement(for: move, in: snapshot)
        else { return false }
        return placeComponents(at: placement, target: target)
    }

    func canReorderComponent(_ direction: ComponentOrderMove) -> Bool {
        !isWorking && !stopped && snapshot?.availableComponentOrderMoves.contains(direction) == true
    }
    func reorderComponent(_ direction: ComponentOrderMove) {
        guard canReorderComponent(direction), let id = snapshot?.selectedComponentID else { return }
        perform { try await $0.apply([.reorderComponent(id: id, direction: direction)]) }
    }
    func canEditComponentWrappingSelection(_ target: ComponentWrappingSelectionTarget) -> Bool {
        guard !stopped, !isWorking, let snapshot else { return false }
        return target.isCurrent(in: snapshot)
    }
    func componentWrappingSelectionAction(_ edit: ComponentWrappingEdit, target: ComponentWrappingSelectionTarget)
        -> @MainActor () -> Void
    {
        guard canEditComponentWrappingSelection(target) else { return {} }
        return { [weak self] in
            guard let self, self.canEditComponentWrappingSelection(target) else { return }
            self.perform(acceptCommittedCancellation: true) {
                try await $0.editSelectedComponentWrapping(edit, target: target)
            }
        }
    }
    func componentWrappingSelectionNumberAction(
        target: ComponentWrappingSelectionTarget, edit: @escaping @MainActor (String) -> ComponentWrappingEdit?
    ) -> @MainActor (String) -> Void {
        guard canEditComponentWrappingSelection(target) else { return { _ in } }
        return { [weak self] text in
            guard let self, self.canEditComponentWrappingSelection(target) else { return }
            guard let value = edit(text) else {
                self.errorMessage = Self.message(DocumentError.invalidComponentWrapping)
                return
            }
            self.componentWrappingSelectionAction(value, target: target)()
        }
    }

    func canEditComponentSurface(_ target: ComponentSurfaceTarget) -> Bool {
        guard !isWorking, !stopped, let snapshot else { return false }
        return target.isCurrent(in: snapshot)
    }
    func componentSurfaceAction(_ edit: ComponentSurfaceEdit, target: ComponentSurfaceTarget) -> @MainActor () -> Void {
        guard canEditComponentSurface(target) else { return {} }
        return { [weak self] in
            guard let self, self.canEditComponentSurface(target) else { return }
            self.perform(acceptCommittedCancellation: true) { try await $0.editComponentSurface(edit, target: target) }
        }
    }
    func componentSurfaceScalarAction(_ property: ComponentSurfaceScalar, target: ComponentSurfaceTarget)
        -> @MainActor (String) -> Void
    {
        guard canEditComponentSurface(target) else { return { _ in } }
        return { [weak self] text in
            guard let self, self.canEditComponentSurface(target) else { return }
            guard let number = EngineScalar.parse(text, in: property.bounds) else {
                self.errorMessage =
                    "Enter a wrapping finish value from \(property.bounds.lowerBound) to \(property.bounds.upperBound)."
                return
            }
            self.componentSurfaceAction(.scalar(property, number), target: target)()
        }
    }
    func componentSurfaceInkAction(target: ComponentSurfaceTarget) -> @MainActor (DocumentColor) -> Void {
        guard canEditComponentSurface(target) else { return { _ in } }
        return { [weak self] color in
            guard let self, self.canEditComponentSurface(target) else { return }
            self.componentSurfaceAction(.ink(color), target: target)()
        }
    }

    func canEditComponentWrapBinding(_ target: ComponentWrapBindingTarget) -> Bool {
        guard !isWorking, !stopped, let snapshot else { return false }
        return target.isCurrent(in: snapshot)
    }
    func componentWrapBindingAction(_ choice: ComponentWrapBindingChoice, target: ComponentWrapBindingTarget)
        -> @MainActor () -> Void
    {
        guard canEditComponentWrapBinding(target) else { return {} }
        return { [weak self] in
            guard let self, self.canEditComponentWrapBinding(target) else { return }
            self.perform(acceptCommittedCancellation: true) {
                try await $0.editComponentWrapBinding(choice, target: target)
            }
        }
    }

    func setComponentWrapMode(_ id: String, mode: ComponentWrapMode) {
        perform { try await $0.apply([.setComponentWrapMode(id: id, mode: mode)]) }
    }
    func setComponentWrapKeepChildren(_ id: String, value: Bool) {
        perform { try await $0.apply([.setComponentWrapKeepChildren(id: id, value: value)]) }
    }
    func setComponentWrapScalar(_ id: String, property: ComponentWrappingScalarProperty, value: String) {
        guard !isWorking, !stopped else { return }
        guard let number = EngineScalar.parse(value, in: property.bounds) else {
            errorMessage = Self.message(DocumentError.invalidComponentWrapping)
            return
        }
        perform { try await $0.apply([.setComponentWrapScalar(id: id, property: property, value: number)]) }
    }
    func setComponentWrapFaces(_ id: String, faces: String) {
        guard !isWorking, !stopped else { return }
        guard let number = Int(faces), (64...20000).contains(number) else {
            errorMessage = Self.message(DocumentError.invalidComponentWrapping)
            return
        }
        perform { try await $0.apply([.setComponentWrapFaces(id: id, faces: number)]) }
    }
    func setComponentStitchingClosure(_ id: String, property: ComponentStitchingClosureProperty, value: Bool) {
        perform { try await $0.apply([.setComponentStitchingClosure(id: id, property: property, value: value)]) }
    }
    func setComponentStitchingScalar(_ id: String, property: ComponentStitchingScalarProperty, value: String) {
        guard !isWorking, !stopped else { return }
        guard let number = EngineScalar.parse(value, in: property.bounds) else {
            errorMessage = Self.message(DocumentError.invalidComponentStitchingScalar)
            return
        }
        perform { try await $0.apply([.setComponentStitchingScalar(id: id, property: property, value: number)]) }
    }
    func setComponentTargetSegments(_ id: String, segments: String) {
        guard !isWorking, !stopped else { return }
        guard let number = Int(segments), (0...100).contains(number) else {
            errorMessage = Self.message(DocumentError.invalidComponentTargetSegments)
            return
        }
        perform { try await $0.apply([.setComponentTargetSegments(id: id, segments: number)]) }
    }
    func setPartFillLoopInterior(_ id: String, value: Bool) {
        perform { try await $0.apply([.setPartFillLoopInterior(id: id, value: value)]) }
    }
    func setPartTarget(_ id: String, target: PartTarget) {
        perform { try await $0.apply([.setPartTarget(id: id, target: target)]) }
    }
    func canEditGraphPartRole(_ target: GraphPartRoleTarget) -> Bool {
        !isWorking && acceptedDocumentSource.map { target.isCurrent(in: $0) } == true
    }

    func setGraphPartRole(_ role: PartTarget, target: GraphPartRoleTarget) {
        guard canEditGraphPartRole(target) else { return }
        perform(acceptCommittedCancellation: true) { try await $0.setGraphPartRole(role, target: target) }
    }

    func setPartCutFace(_ id: String, selection: CutFaceSelection) {
        perform { try await $0.apply([.setPartCutFace(id: id, selection: selection)]) }
    }
    func setPartCutRotation(_ id: String, rotation: String) {
        guard !isWorking, !stopped else { return }
        guard let value = EngineScalar.parse(rotation, in: -1...1) else {
            errorMessage = Self.message(DocumentError.invalidPartCutRotation)
            return
        }
        perform { try await $0.apply([.setPartCutRotation(id: id, rotation: value)]) }
    }
    func partCutRotationPresetAction(_ preset: PartCutRotationPreset, partID: String) -> @MainActor () -> Void {
        guard let snapshot = acceptedDocumentSource, snapshot.cutRotationPresets(for: partID).contains(preset)
        else { return {} }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        return { [weak self] in
            guard let self, !self.stopped, !self.isWorking, let current = self.acceptedDocumentSource,
                target.isCurrent(in: current)
            else { return }
            self.perform { try await $0.setPartCutRotationPreset(preset, partID: partID, target: target) }
        }
    }

    func canEditGraphPartCrossSection(_ target: GraphPartCrossSectionTarget) -> Bool {
        !isWorking && acceptedDocumentSource.map { target.isCurrent(in: $0) } == true
    }

    func editGraphPartCrossSection(_ edit: GraphPartCrossSectionEdit, target: GraphPartCrossSectionTarget) {
        guard canEditGraphPartCrossSection(target) else { return }
        perform(acceptCommittedCancellation: true) {
            try await $0.editGraphPartCrossSection(edit, target: target)
        }
    }

    func setGraphPartCutRotation(_ rotation: String, target: GraphPartCrossSectionTarget) {
        guard canEditGraphPartCrossSection(target) else { return }
        guard let value = EngineScalar.parse(rotation, in: -1...1) else {
            errorMessage = Self.message(DocumentError.invalidPartCutRotation)
            return
        }
        editGraphPartCrossSection(.rotation(value), target: target)
    }

    func setPartMaterial(_ id: String, property: PartMaterialProperty, value: String) {
        guard !isWorking, !stopped, let scalar = parsePartMaterial(value, property: property) else { return }
        perform {
            try await $0.apply([.setPartMaterial(id: id, property: property, value: scalar)])
        }
    }

    func canEditGraphPartMaterial(_ target: GraphModelPartTarget) -> Bool {
        !isWorking && acceptedDocumentSource.map { target.isCurrent(in: $0) } == true
    }

    func setGraphPartMaterial(_ property: PartMaterialProperty, value: String, target: GraphModelPartTarget) {
        guard canEditGraphPartMaterial(target), let scalar = parsePartMaterial(value, property: property) else {
            return
        }
        commitGraphPartMaterial(property, value: scalar, target: target)
    }

    func resetGraphPartMaterial(_ property: PartMaterialProperty, target: GraphModelPartTarget) {
        guard canEditGraphPartMaterial(target) else { return }
        commitGraphPartMaterial(property, value: property.defaultValue, target: target)
    }

    private func parsePartMaterial(_ value: String, property: PartMaterialProperty) -> Double? {
        guard let scalar = EngineScalar.parse(value, in: property.bounds) else {
            errorMessage = "Enter a value from 0 to \(Int(property.bounds.upperBound)) that the material can represent."
            return nil
        }
        return scalar
    }

    private func commitGraphPartMaterial(_ property: PartMaterialProperty, value: Double, target: GraphModelPartTarget)
    {
        perform(acceptCommittedCancellation: true) {
            try await $0.setGraphPartMaterial(property, value: value, target: target)
        }
    }
    #if MOTE3D_EXPERIMENTAL_HOLLOW
        func setExperimentalHollowThickness(_ id: String, value: String) {
            guard !stopped, !isWorking, let snapshot, snapshot.selectedPart?.id == id,
                snapshot.selectedPart?.target == .model
            else { return }
            let target = CanvasAdjustmentTarget(snapshot: snapshot)
            perform {
                guard let thickness = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw DocumentError.invalidPartHollowThickness
                }
                return try await $0.setPartHollowThickness(id: id, thickness: thickness, target: target)
            }
        }
    #endif

    func setNodeDeformationScale(
        _ property: PartDeformationProperty, draft: String, nodeID: String, target: CanvasAdjustmentTarget
    ) {
        guard !stopped, !isWorking, let snapshot, target.isCurrent(in: snapshot),
            snapshot.allowsNodeDeformation(for: nodeID)
        else { return }
        guard let value = NodeDeformation.parse(draft) else {
            errorMessage = Self.message(DocumentError.invalidNodeDeformation)
            return
        }
        perform {
            try await $0.setNodeDeformationScale(property, value: value, nodeID: nodeID, target: target)
        }
    }

    func setGraphPartDeformationScale(
        _ property: PartDeformationProperty, value: String, target: GraphPartCrossSectionTarget
    ) {
        guard canEditGraphPartCrossSection(target) else { return }
        guard let scale = EngineScalar.parse(value, in: 0...2) else {
            errorMessage = Self.message(DocumentError.invalidPartDeformation)
            return
        }
        editGraphPartCrossSection(.deformationScale(property, scale), target: target)
    }

    func setPartDeformationScale(_ id: String, property: PartDeformationProperty, value: String) {
        guard !isWorking, !stopped else { return }
        guard let scale = EngineScalar.parse(value, in: 0...2) else {
            errorMessage = Self.message(DocumentError.invalidPartDeformation)
            return
        }
        perform { try await $0.apply([.setPartDeformationScale(id: id, property: property, value: scale)]) }
    }
    func partDeformationResetAction(
        _ property: PartDeformationProperty, partID: String
    ) -> (@MainActor () -> Void)? {
        guard let snapshot, let part = snapshot.inspectedPart, part.target == .model,
            part.id.utf8.elementsEqual(partID.utf8)
        else { return nil }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        return { [weak self] in
            guard let self, !self.stopped, !self.isWorking, let current = self.snapshot,
                target.isCurrent(in: current)
            else { return }
            self.perform { try await $0.resetPartDeformationScale(property, partID: partID, target: target) }
        }
    }

    func setPartDeformationUnified(_ id: String, value: Bool) {
        perform { try await $0.apply([.setPartDeformationUnified(id: id, value: value)]) }
    }
    func setPartModifier(_ id: String, property: PartModifierProperty, value: Bool) {
        perform { try await $0.apply([.setPartModifier(id: id, property: property, value: value)]) }
    }
    func canEditPartMirror(_ target: PartMirrorTarget) -> Bool {
        !isWorking && acceptedDocumentSource.map { target.isCurrent(in: $0) } == true
    }

    func partMirrorAction(_ value: Bool, target: PartMirrorTarget) -> @MainActor () -> Void {
        { [weak self] in
            guard let self, self.canEditPartMirror(target) else { return }
            self.perform(acceptCommittedCancellation: true) { try await $0.setPartXMirrored(value, target: target) }
        }
    }

    func canEditGraphPartShape(_ target: GraphPartShapeTarget) -> Bool {
        !isWorking && acceptedDocumentSource.map { target.isCurrent(in: $0) } == true
    }

    func setGraphPartShape(_ property: PartModifierProperty, value: Bool, target: GraphPartShapeTarget) {
        guard canEditGraphPartShape(target) else { return }
        perform(acceptCommittedCancellation: true) {
            try await $0.setGraphPartShape(property, value: value, target: target)
        }
    }

    func canAssignBoneName(_ name: String, target: EdgeBoneAssignmentTarget) -> Bool {
        guard !isWorking, let source = acceptedDocumentSource else { return false }
        return target.isCurrent(in: source) && target.hasChanges(name: name)
    }

    func canAssignTemplateBoneName(_ name: String, target: EdgeBoneAssignmentTarget) -> Bool {
        !isAddingNodes && !isMovingOrigin && !referenceColorInteractionActive && canAssignBoneName(name, target: target)
    }
    func assignBoneNameAction(_ name: String, target: EdgeBoneAssignmentTarget) -> @MainActor () -> Void {
        guard canAssignBoneName(name, target: target) else { return {} }
        return { [weak self] in
            guard let self, self.canAssignBoneName(name, target: target) else { return }
            self.perform(acceptCommittedCancellation: true) { try await $0.assignBoneName(name, target: target) }
        }
    }

    private struct BoneEdgeHoverPresentation {
        let owner: BoneEdgeHoverOwner
        let target: BoneEdgeSelectionTarget
    }
    private var boneEdgeHover: BoneEdgeHoverPresentation?
    var highlightedBoneEdgeIDs: Set<String> {
        guard !stopped, !isWorking, let snapshot, let hover = boneEdgeHover,
            hover.target.isCurrent(in: snapshot)
        else { return [] }
        return hover.target.matchingEdgeIDs
    }
    func canSelectBoneEdges(_ target: BoneEdgeSelectionTarget) -> Bool {
        guard !stopped, !isWorking, let snapshot else { return false }
        return target.isCurrent(in: snapshot)
    }
    func boneEdgeSelectionAction(_ target: BoneEdgeSelectionTarget) -> @MainActor () -> Void {
        guard canSelectBoneEdges(target) else { return {} }
        return { [weak self] in
            guard let self, self.canSelectBoneEdges(target) else { return }
            self.boneEdgeHover = nil
            self.perform(commits: false, acceptCommittedCancellation: true, selectionOnly: true) {
                try await $0.selectBoneEdges(target: target)
            }
        }
    }
    func boneEdgeHoverAction(_ target: BoneEdgeSelectionTarget, owner: BoneEdgeHoverOwner) -> @MainActor (Bool) -> Void
    {
        guard canSelectBoneEdges(target), !target.matchingEdgeIDs.isEmpty else { return { _ in } }
        return { [weak self] entering in
            guard let self else { return }
            if entering {
                guard self.canSelectBoneEdges(target) else { return }
                self.boneEdgeHover = .init(owner: owner, target: target)
            } else if self.boneEdgeHover?.owner == owner, self.boneEdgeHover?.target == target {
                // An old exit must not erase another row or a newer source epoch on this row.
                self.boneEdgeHover = nil
            }
        }
    }

    func canClearBoneAssignments(_ target: BoneAssignmentClearTarget) -> Bool {
        guard !stopped, !isWorking, let snapshot else { return false }
        return target.isCurrent(in: snapshot)
    }
    func clearBoneAssignmentsAction(_ target: BoneAssignmentClearTarget) -> @MainActor () -> Void {
        guard canClearBoneAssignments(target) else { return {} }
        return { [weak self] in
            guard let self, self.canClearBoneAssignments(target) else { return }
            self.perform(acceptCommittedCancellation: true) { try await $0.clearBoneAssignments(target: target) }
        }
    }

    func setEdgeBoneName(_ id: String, name: String) {
        perform { try await $0.apply([.setEdgeBoneName(id: id, name: name)]) }
    }
    func selectedParts(for target: ComponentMeshSelectionTarget) -> [DocumentPart] {
        guard !stopped, !isWorking, let snapshot, target.isCurrent(in: snapshot) else { return [] }
        let ids = Set(snapshot.selectedComponentRows.compactMap { $0.component.partID }.map { Data($0.utf8) })
        return snapshot.parts.filter { ids.contains(Data($0.id.utf8)) }
    }

    func setSelectedComponentPartState(_ property: PartStateProperty, value: Bool, target: ComponentMeshSelectionTarget)
    {
        guard selectedParts(for: target).contains(where: { $0.state(property) != value }) else { return }
        perform(acceptCommittedCancellation: true) {
            try await $0.setSelectedComponentPartState(property, value: value, target: target)
        }
    }

    func canEditSelectedComponentColors(_ target: ComponentMeshSelectionTarget) -> Bool {
        acceptedDocumentSource != nil && canEditComponentMeshSettings(target)
    }

    func setSelectedComponentColors(_ target: ComponentMeshSelectionTarget, value: String?) {
        guard canEditSelectedComponentColors(target) else { return }
        let color = value.flatMap { DocumentColor(archiveValue: $0) }
        if value != nil, color == nil {
            errorMessage = Self.message(DocumentError.invalidComponentColor)
            return
        }
        perform(acceptCommittedCancellation: true) { try await $0.editSelectedComponentColors(color, target: target) }
    }

    func setComponentColor(_ id: String, value: String) {
        guard !isWorking, !stopped else { return }
        guard let color = DocumentColor(archiveValue: value) else {
            errorMessage = Self.message(DocumentError.invalidComponentColor)
            return
        }
        perform { try await $0.apply([.setComponentColor(id: id, color: color)]) }
    }
    func removeComponentColor(_ id: String) {
        perform { try await $0.apply([.setComponentColor(id: id, color: nil)]) }
    }
    func setComponentSmoothCutoff(_ id: String, degrees: String) {
        guard !isWorking, !stopped else { return }
        guard let value = Double(degrees), value.isFinite, (0...180).contains(value) else {
            errorMessage = Self.message(DocumentError.invalidComponentSmoothing)
            return
        }
        perform { try await $0.apply([.setComponentSmoothCutoffDegrees(id: id, degrees: value)]) }
    }
    func setComponentCombineMode(_ id: String, mode: ComponentCombineMode) {
        perform { try await $0.apply([.setComponentCombineMode(id: id, mode: mode)]) }
    }
    func renameComponent(_ id: String, name: String) {
        perform { try await $0.apply([.setComponentName(id: id, name: name)]) }
    }
    func canEditComponentEquipmentSlot(_ target: ComponentEquipmentSlotTarget) -> Bool {
        !isWorking && acceptedDocumentSource.map { target.isCurrent(in: $0) } == true
    }

    func setComponentEquipmentSlot(_ slot: String, target: ComponentEquipmentSlotTarget) {
        guard canEditComponentEquipmentSlot(target) else { return }
        perform { try await $0.setComponentEquipmentSlot(slot, target: target) }
    }

    func selectPart(_ id: String?) { perform(commits: false) { try await $0.selectPart(id) } }
    var originInspectorSource: OriginInspectorSource? {
        acceptedDocumentSource.map { .init(documentIdentity: $0.documentIdentity, origin: $0.origin) }
    }

    func originInspectorApplyAction(source: OriginInspectorSource) -> (@MainActor (String, String, String) -> Void)? {
        guard !isWorking, let snapshot = acceptedDocumentSource, originInspectorSource == source else { return nil }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        return { [weak self] x, y, z in
            guard let self, let current = self.acceptedDocumentSource, target.isCurrent(in: current) else { return }
            self.setOrigin(x: x, y: y, z: z, target: target)
        }
    }

    func setOrigin(x: String, y: String, z: String, target: CanvasAdjustmentTarget? = nil) {
        guard !isWorking, !stopped else { return }
        guard let x = Double(x), let y = Double(y), let z = Double(z) else {
            errorMessage = Self.message(DocumentError.invalidOrigin)
            return
        }
        perform { try await $0.apply([.setOrigin(.init(x: x, y: y, z: z))], selecting: nil, target: target) }
    }
    func centerOriginOnModel() {
        perform { try await $0.centerOriginOnModel() }
    }
    func renamePart(_ id: String, name: String) {
        perform { try await $0.apply([.setPartName(id: id, name: name)]) }
    }
    func canvasPartStateAction(_ property: PartStateProperty) -> (@MainActor () -> Void)? {
        let lease = canvasProfiles.isDualProfile ? canvasProfiles.lease : nil
        guard let handle = canvasPartStateHandler(profileLease: lease) else { return nil }
        return { _ = handle(property, false) }
    }

    func canvasPartStateKeyHandler(profileLease: UUID?) -> @MainActor (CanvasPrecisionKeyInput) -> Bool {
        let handle = canvasPartStateHandler(profileLease: profileLease)
        return { input in
            guard let property = input.partStateProperty, let handle else { return false }
            return handle(property, input.isRepeat)
        }
    }

    private var canToggleCanvasPartState: Bool {
        canSave && !isSelectingRigEdges && !isAddingNodes && !isMovingOrigin
            && !referenceColorInteractionActive && canvasProfileMotion == nil
    }

    private func canvasPartStateHandler(profileLease: UUID?) -> (@MainActor (PartStateProperty, Bool) -> Bool)? {
        guard canToggleCanvasPartState, ownsCanvasProfile(profileLease), let snapshot = acceptedDocumentSource,
            let context = canvasRotationContext
        else { return nil }
        let hover: PartGraphTarget? =
            switch canvasPartStateHover {
            case .node(let id): .node(id)
            case .edge(let id): .edge(id)
            case nil: nil
            }
        guard let target = CanvasPartStateTarget(snapshot: snapshot, hovered: hover) else { return nil }
        let hoverEpoch = canvasPartStateHoverEpoch
        let layout = precisionLayoutEpoch
        let interaction = referenceColorInteractionEpoch
        return { [weak self] property, isRepeat in
            guard let self, canToggleCanvasPartState, ownsCanvasProfile(profileLease),
                canvasRotationContext == context, canvasPartStateHoverEpoch == hoverEpoch,
                precisionLayoutEpoch == layout, referenceColorInteractionEpoch == interaction,
                property == .locked || property == .disabled
            else { return false }
            if !isRepeat {
                // A lock changes editability while the same visible graph item remains under the pointer.
                perform(acceptCommittedCancellation: true, preservePartStateHover: property == .locked) {
                    try await $0.toggleCanvasPartState(property, target: target)
                }
            }
            return true
        }
    }

    func setPartState(_ id: String, property: PartStateProperty, value: Bool) {
        perform {
            try await $0.apply([.setPartState(id: id, property: property, value: value)])
        }
    }
    func toggleSelection(_ id: String) {
        guard !isSelectingRigEdges else { return }
        perform(commits: false, selectionOnly: true) { try await $0.toggleSelection(id) }
    }
    func selectAllNodes() {
        guard !isSelectingRigEdges else { return }
        perform(commits: false, selectionOnly: true) { try await $0.selectAllNodes() }
    }

    func selectAll() {
        if isSelectingRigEdges, let snapshot {
            selectEdges(Set(rigEdgePickCandidates(in: snapshot, mode: .replace).map(\.id)))
        } else {
            perform(commits: false, selectionOnly: true) { try await $0.selectAll() }
        }
    }
    func move(id: String, to position: NodePosition) { perform { try await $0.move(id: id, to: position) } }

    func commitNodeDrag(_ drag: NodeDrag, translation: CanvasPoint) {
        guard !isSelectingRigEdges else { return }
        perform { try await $0.commitNodeDrag(drag, translation: translation) }
    }
    func commitCanvasShiftDrag(_ drag: CanvasShiftDrag, translation: CanvasPoint) {
        guard !isSelectingRigEdges, !isWorking, !stopped, !isAddingNodes, !isMovingOrigin, let snapshot,
            drag.projection.plane == plane, drag.isCurrent(in: snapshot)
        else { return }
        perform { try await $0.commitCanvasShiftDrag(drag, translation: translation) }
    }

    func bendEndpoint(_ target: EndpointIKTarget, toward destination: NodePosition, context: CanvasRotationContext) {
        guard !isSelectingRigEdges, !isWorking, !stopped, !isAddingNodes, !isMovingOrigin, let snapshot,
            canvasRotationContext == context, target.isCurrent(in: snapshot), target.canBend
        else { return }
        perform { try await $0.bendEndpoint(target, toward: destination) }
    }

    func moveSelection(by delta: NodePosition) {
        guard canTransform, let snapshot,
            let effective = SelectionTransformInput.move(delta: delta, locks: snapshot.locks)
        else { return }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        perform { try await $0.moveSelection(by: effective, target: target) }
    }

    func scaleSelection(positionFactor: Double, radiusFactor: Double) {
        guard canTransform, let snapshot,
            let effective = SelectionTransformInput.scale(
                positionFactor: positionFactor, radiusFactor: radiusFactor, locks: snapshot.locks)
        else { return }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        perform {
            try await $0.scaleSelection(
                positionFactor: effective.positionFactor, radiusFactor: effective.radiusFactor, target: target)
        }
    }
    var canTransform: Bool {
        !isSelectingRigEdges && !isWorking && snapshot?.transformNodes.contains(where: \.isEditable) == true
    }
    func canTransformSelection(_ transform: SelectionTransform) -> Bool {
        !isSelectingRigEdges && !isWorking && !stopped && snapshot.map { transform.canApply(in: $0) } == true
    }
    func canPerformCanvasPrecision(_ action: CanvasPrecisionAction) -> Bool {
        guard !isSelectingRigEdges, canSave, !isAddingNodes, !referenceColorInteractionActive, originDrag == nil,
            canvasHeight.isFinite, canvasHeight > 0, let snapshot
        else { return false }
        if action.isSpacing {
            let factor = 1 + (action == .increaseSpacing ? 10 : -10) / canvasHeight
            return factor.isFinite && !locks.isSuperset(of: [.x, .y, .z])
                && snapshot.transformNodes.contains(where: \.isEditable)
        }
        let vertical = action == .up || action == .down
        let axis: EditingConstraint = vertical ? .y : (plane == .front ? .x : .z)
        guard !locks.contains(axis) else { return false }
        return isMovingOrigin ? snapshot.origin != nil : snapshot.transformNodes.contains(where: \.isEditable)
    }
    func canvasPrecisionAction(_ action: CanvasPrecisionAction) -> @MainActor () -> Void {
        let handler = canvasPrecisionHandler()
        let admitted = canPerformCanvasPrecision(action)
        return { if admitted { _ = handler(action) } }
    }
    func canvasPrecisionKeyHandler() -> @MainActor (CanvasPrecisionKeyInput) -> Bool {
        let handler = canvasPrecisionHandler()
        return { input in
            guard let action = input.action else { return false }
            return handler(action)
        }
    }
    private func canvasPrecisionHandler() -> @MainActor (CanvasPrecisionAction) -> Bool {
        let target = snapshot.map(CanvasAdjustmentTarget.init)
        let capturedPlane = plane
        let height = canvasHeight
        let layout = precisionLayoutEpoch
        let tool = rotationInputContextID
        let add = addModeID
        let interaction = referenceColorInteractionEpoch
        return { [weak self] action in
            guard let self, let target, let snapshot = self.snapshot, target.isCurrent(in: snapshot),
                self.precisionLayoutEpoch == layout, self.rotationInputContextID == tool,
                self.addModeID == add, self.referenceColorInteractionEpoch == interaction,
                self.canPerformCanvasPrecision(action)
            else { return false }
            self.dispatchCanvasPrecision(action, height: height, plane: capturedPlane, target: target)
            return true
        }
    }
    func performCanvasPrecision(_ action: CanvasPrecisionAction) { canvasPrecisionAction(action)() }
    private func dispatchCanvasPrecision(
        _ action: CanvasPrecisionAction, height: Double, plane: EditingPlane,
        target: CanvasAdjustmentTarget
    ) {
        let preservesOriginMode = isMovingOrigin
        if action.isSpacing {
            let factor = 1 + (action == .increaseSpacing ? 10 : -10) / height
            perform(acceptCommittedCancellation: true, preserveOriginMode: preservesOriginMode) {
                try await $0.scaleSelectionPositions(factor: factor, target: target)
            }
        } else {
            let horizontal = action == .left ? -1.0 : (action == .right ? 1 : 0)
            let vertical = action == .up ? -1.0 : (action == .down ? 1 : 0)
            let delta = NodePosition(
                x: plane == .front ? horizontal / height : 0,
                y: vertical / height, z: plane == .side ? horizontal / height : 0)
            if preservesOriginMode {
                perform(acceptCommittedCancellation: true, preserveOriginMode: true) {
                    try await $0.nudgeOrigin(by: delta, target: target)
                }
            } else {
                perform(acceptCommittedCancellation: true) { try await $0.moveSelection(by: delta, target: target) }
            }
        }
    }
    var canRotateCanvasSelection: Bool { canRotateCanvasSelection(in: plane) }

    private func canRotateCanvasSelection(in plane: EditingPlane) -> Bool {
        guard !isSelectingRigEdges, canSave, !isAddingNodes, !isMovingOrigin, let snapshot else { return false }
        return snapshot.canRotateSelection(in: plane)
    }

    func canvasRotationAction(degrees: Double) -> @MainActor () -> Void {
        let commit = canvasRotationHandler()
        return { commit(degrees) }
    }
    var canvasRotationContext: CanvasRotationContext? {
        snapshot.map {
            CanvasRotationContext(
                target: CanvasAdjustmentTarget(snapshot: $0), plane: plane,
                inputEpoch: rotationInputContextID, addModeEpoch: addModeID)
        }
    }

    /// Retain the rendered context while validating the displayed angle at submit.
    func canvasRotationHandler() -> @MainActor (Double) -> Void {
        let context = canvasRotationContext
        return { [weak self] degrees in
            guard let self, let context, self.canvasRotationContext == context else { return }
            self.rotateCanvasSelection(degrees: degrees, target: context.target, plane: context.plane)
        }
    }
    func rotateCanvasSelection(degrees: Double, target: CanvasAdjustmentTarget? = nil, plane: EditingPlane? = nil) {
        let capturedPlane = plane ?? self.plane
        guard canRotateCanvasSelection(in: capturedPlane), let snapshot else { return }
        let capturedTarget = target ?? CanvasAdjustmentTarget(snapshot: snapshot)
        perform { try await $0.rotateSelection(degrees: degrees, plane: capturedPlane, target: capturedTarget) }
    }
    @discardableResult
    func handleCanvasRotationInput(
        characters: String, modifiers: NSEvent.ModifierFlags,
        animationFocus: Bool, nativeTextFocus: Bool
    ) -> Bool {
        guard canRotateCanvasSelection,
            let degrees = CanvasRotationInput.degrees(
                characters: characters, modifiers: modifiers,
                animationFocus: animationFocus, nativeTextFocus: nativeTextFocus)
        else { return false }
        rotateCanvasSelection(degrees: degrees)
        return true
    }
    private func canRotateOrthogonalQuarterTurn(profileLease: UUID?) -> Bool {
        !isSelectingRigEdges && canSave && !isAddingNodes && !isMovingOrigin && !referenceColorInteractionActive
            && ownsCanvasProfile(profileLease) && snapshot?.canRotateOrthogonalQuarterTurn(from: plane) == true
    }

    func orthogonalQuarterTurnAction(
        _ turn: OrthogonalQuarterTurn, profileLease: UUID? = nil
    ) -> (@MainActor () -> Void)? {
        guard canRotateOrthogonalQuarterTurn(profileLease: profileLease), let context = canvasRotationContext else {
            return nil
        }
        let interaction = referenceColorInteractionEpoch
        return { [weak self] in
            guard let self, self.canvasRotationContext == context,
                self.referenceColorInteractionEpoch == interaction,
                self.canRotateOrthogonalQuarterTurn(profileLease: profileLease)
            else { return }
            self.perform {
                try await $0.rotateOrthogonalQuarterTurn(turn, from: context.plane, target: context.target)
            }
        }
    }

    var canRotateDescendants: Bool {
        !isSelectingRigEdges && !isWorking && snapshot?.canRotateDescendants == true
    }
    func rotateDescendants(_ rotation: DescendantRotation) {
        guard !isSelectingRigEdges else { return }
        perform { try await $0.rotateDescendants(rotation) }
    }
    func transformSelection(_ transform: SelectionTransform) {
        guard canTransformSelection(transform) else { return }
        perform { try await $0.transformSelection(transform) }
    }
    var canReduceSelectedNodes: Bool { !isWorking && snapshot?.canReduceSelectedNodes == true }

    func reduceSelectedNodes() {
        guard canReduceSelectedNodes else { return }
        perform { try await $0.reduceSelectedNodes() }
    }

    var canInsertEdgeMidpoint: Bool { !isWorking && snapshot?.canInsertSelectedEdgeMidpoints == true }
    var canReverseSelectedEdges: Bool { !isWorking && snapshot?.canEditSelectedEdges == true }
    var canDeleteGraphSelection: Bool { canSave && snapshot?.canDeleteSelection == true }

    func insertSelectedEdgeMidpoints() {
        guard canInsertEdgeMidpoint else { return }
        perform { try await $0.insertSelectedEdgeMidpoints() }
    }
    func reverseExplicitlySelectedEdges() {
        guard canReverseSelectedEdges else { return }
        perform { try await $0.reverseExplicitlySelectedEdges() }
    }

    func insertSelectedEdgeMidpoint() {
        guard canInsertEdgeMidpoint else { return }
        perform { try await $0.insertSelectedEdgeMidpoint() }
    }

    func reverseSelectedEdges() { perform { try await $0.reverseSelectedEdges() } }
    func reverseEdge(_ id: String) { perform { try await $0.apply([.reverseEdges([id])]) } }

    var canCopyNodes: Bool { !isWorking && snapshot?.canCopyNodes == true }
    var canCutNodes: Bool { canSave && snapshot?.canCutNodes == true }

    /// Clipboard promise registration succeeds before a Cut can mutate the document.
    func copyNodes(cut: Bool = false, to pasteboard: any EditorClipboardWriting) {
        guard cut ? canCutNodes : canCopyNodes, !stopped else { return }
        let sourceIdentity = acceptedDocumentSource?.documentIdentity
        cancelColorImagePreparation()
        cancelOriginDrag()
        let requestID = UUID()
        operationRequestID = requestID
        isWorking = true
        operation = Task {
            defer { if operationRequestID == requestID { isWorking = false } }
            do {
                let data = try await session.copyRepresentations(identifier: UUID().uuidString, onlyEditable: cut)
                guard !Task.isCancelled, !stopped, operationRequestID == requestID else { return }
                try pasteboard.write(data.native, snapshotXML: data.snapshotXML)
                if cut {
                    guard !Task.isCancelled, operationRequestID == requestID,
                        let sourceIdentity, acceptedDocumentSource?.documentIdentity == sourceIdentity
                    else { return }
                    let next = try await session.deleteSelection()
                    guard !Task.isCancelled, !stopped, operationRequestID == requestID else { return }
                    snapshot = next
                    fit()
                    onDocumentChanged?(next.document.encoded())
                    generate(next)
                }
                if operationRequestID == requestID, acceptedDocumentSource != nil { errorMessage = nil }
            } catch {
                if !Task.isCancelled, operationRequestID == requestID, acceptedDocumentSource != nil {
                    errorMessage = Self.message(error)
                }
            }
        }
    }

    struct ClipboardPasteRequest: Hashable, Sendable {
        fileprivate let context: CanvasAdjustmentTarget
        fileprivate let workingGroupRevision: UUID
        fileprivate let parentID: String?
    }

    func clipboardPasteRequest() -> ClipboardPasteRequest? {
        guard canSave, let snapshot, case .success(let accepted) = recoveryLoadResult,
            accepted.documentIdentity == snapshot.documentIdentity
        else { return nil }
        let parentID: String?
        if case .group(let id) = effectiveAddPlacementDestination {
            guard snapshot.addPlacementGroup(id) != nil else { return nil }
            parentID = id
        } else {
            parentID = nil
        }
        return ClipboardPasteRequest(
            context: CanvasAdjustmentTarget(snapshot: snapshot), workingGroupRevision: workingGroupRevision,
            parentID: parentID)
    }

    func pasteNodes(data: Data) {
        guard let request = clipboardPasteRequest() else { return }
        pasteNodes(data: data, request: request)
    }

    func pasteNodes(data: Data, request: ClipboardPasteRequest) {
        guard request == clipboardPasteRequest() else { return }
        perform(reloadReferenceImage: true, acceptCommittedCancellation: true) {
            try await $0.paste(data: data, parentID: request.parentID, target: request.context)
        }
    }

    private struct QtXMLFilePasteRequest {
        let id = UUID()
        let fileIdentity: UUID
        let clipboard: ClipboardPasteRequest
    }

    private var qtXMLFilePasteRequest: QtXMLFilePasteRequest?
    var qtXMLFilePasteRequestID: UUID? { qtXMLFilePasteRequest?.id }
    var canChooseQtXMLFile: Bool {
        qtXMLFilePasteRequest == nil && acceptedQtXMLFileSource != nil
    }

    private var acceptedQtXMLFileSource: (clipboard: ClipboardPasteRequest, fileIdentity: UUID)? {
        guard let clipboard = clipboardPasteRequest(), case .success(let accepted) = recoveryLoadResult,
            let fileIdentity = accepted.fileIdentity
        else { return nil }
        return (clipboard, fileIdentity)
    }

    private func isCurrentQtXMLFileSource(_ request: QtXMLFilePasteRequest) -> Bool {
        guard !stopped, let snapshot, case .success(let accepted) = recoveryLoadResult,
            accepted.fileIdentity == request.fileIdentity, accepted.documentIdentity == snapshot.documentIdentity,
            request.clipboard.workingGroupRevision == workingGroupRevision,
            request.clipboard.context.isCurrent(in: snapshot)
        else { return false }
        if let parentID = request.clipboard.parentID { return snapshot.addPlacementGroup(parentID) != nil }
        return true
    }

    func chooseQtXMLFile() {
        guard qtXMLFilePasteRequest == nil, let source = acceptedQtXMLFileSource else { return }
        qtXMLFilePasteRequest = QtXMLFilePasteRequest(
            fileIdentity: source.fileIdentity, clipboard: source.clipboard)
    }

    func cancelQtXMLFileChoice(requestID: UUID) {
        guard qtXMLFilePasteRequestID == requestID else { return }
        qtXMLFilePasteRequest = nil
    }

    @discardableResult
    func finishQtXMLFileChoice(
        requestID: UUID, result: Result<[URL], any Error>,
        read: @escaping @Sendable (URL) async throws -> Data = { try await QtXMLFileReader().read($0) }
    ) -> Task<Void, Never>? {
        guard let request = qtXMLFilePasteRequest, request.id == requestID else { return nil }
        qtXMLFilePasteRequest = nil
        guard !isWorking, isCurrentQtXMLFileSource(request) else { return nil }
        do {
            let urls = try result.get()
            guard urls.count == 1, let url = urls.first else { throw QtXMLFileReader.Failure.invalidFile }
            perform(acceptCommittedCancellation: true) { [weak self] session in
                let data = try await read(url)
                try Task.checkCancellation()
                guard await self?.isCurrentQtXMLFileSource(request) == true else {
                    throw QtXMLFilePasteError.staleTarget
                }
                return try await session.pasteQtXMLFile(
                    data, target: request.clipboard.context, parentID: request.clipboard.parentID,
                    clearsMissingCutFaces: true)
            }
            return operation
        } catch {
            if (error as? CocoaError)?.code != .userCancelled { errorMessage = Self.message(error) }
            return nil
        }
    }

    @discardableResult
    func applyStartupQtXML(_ data: Data, fileIdentity: UUID) -> Task<Void, Never>? {
        guard !Task.isCancelled, !isWorking, qtXMLFilePasteRequest == nil, let snapshot = acceptedDocumentSource,
            snapshot.documentRevision == 0, case .success(let accepted) = recoveryLoadResult,
            accepted.fileIdentity == fileIdentity
        else { return nil }
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        perform(acceptCommittedCancellation: true) { session in
            try await session.pasteQtXMLFile(data, target: target, parentID: nil, selectsEditableGraph: false)
        }
        return operation
    }

    func pasteQtNodes(snapshotXML: Data) {
        guard let request = clipboardPasteRequest() else { return }
        pasteQtNodes(snapshotXML: snapshotXML, request: request)
    }

    func pasteQtNodes(snapshotXML: Data, request: ClipboardPasteRequest) {
        guard request == clipboardPasteRequest() else { return }
        perform(reloadReferenceImage: true, acceptCommittedCancellation: true) {
            try await $0.paste(snapshotXML: snapshotXML, parentID: request.parentID, target: request.context)
        }
    }

    func deleteSelection() { perform { try await $0.deleteSelection() } }

    func edit(id: String, position: NodePosition, radius: Double) {
        perform { try await $0.edit(id: id, position: position, radius: radius) }
    }

    var canAddNode: Bool { acceptedAddPlacementSource?.canAddNode == true }
    var canAddNewPart: Bool { acceptedAddPlacementSource != nil }

    func addNodeAction(newPart: Bool = false) -> @MainActor () -> Void {
        capturedAddPlacementAction(snapshot: acceptedAddPlacementSource) { store, _ in
            store.addNode(newPart: newPart)
        }
    }

    func addNode(newPart: Bool = false) {
        guard let snapshot = acceptedAddPlacementSource, newPart || snapshot.canAddNode else { return }
        let selected = newPart ? nil : snapshot.selectedNode
        let nodeID = Self.identifier()
        let partID = selected?.partID ?? Self.identifier()
        let position = newPart ? NodePosition(x: 0.5, y: 0.5, z: 0.5) : snapshot.nextNodePosition
        let componentID = selected?.partID == nil ? Self.identifier() : nil
        var commands: [DocumentCommand] = [
            .addNode(
                id: nodeID, partID: partID, componentID: componentID,
                position: position, radius: selected?.value.radius ?? 0.1)
        ]
        // An anchored extension stays in its original part, regardless of the authoring destination.
        if let selected, selected.partID != nil {
            commands.append(.joinNodes(id: Self.identifier(), from: selected.id, to: nodeID))
        } else if let componentID, case .group(let parentID) = effectiveAddPlacementDestination {
            guard snapshot.addPlacementGroup(parentID) != nil else { return }
            commands.append(.reparentComponent(id: componentID, parentID: parentID))
        }
        let transaction = commands
        let target = CanvasAdjustmentTarget(snapshot: snapshot)
        perform(acceptCommittedCancellation: true) {
            try await $0.apply(transaction, selecting: nodeID, target: target)
        }
    }

    func canConnectSelectedNodes(_ target: NodeConnectionTarget, ownerID: String? = nil) -> Bool {
        guard !stopped, !isWorking, let snapshot, target.isCurrent(in: snapshot) else { return false }
        guard let ownerID else { return true }
        return target.owners.contains { $0.nodeID.utf8.elementsEqual(ownerID.utf8) }
    }
    func nodeConnectionAction(_ target: NodeConnectionTarget, ownerID: String) -> @MainActor () -> Void {
        guard canConnectSelectedNodes(target, ownerID: ownerID) else { return {} }
        return { [weak self] in
            guard let self, self.canConnectSelectedNodes(target, ownerID: ownerID) else { return }
            self.perform(acceptCommittedCancellation: true) {
                try await $0.connectSelectedNodes(target: target, ownerID: ownerID)
            }
        }
    }

    func canPerformGraphSelectionAction(_ target: GraphSelectionActionTarget) -> Bool {
        guard !stopped, !isWorking, !isAddingNodes, !isMovingOrigin, !referenceColorInteractionActive,
            let snapshot
        else { return false }
        return target.isAvailable && target.isCurrent(in: snapshot)
    }

    func graphSelectionAction(_ target: GraphSelectionActionTarget) -> @MainActor () -> Void {
        guard canPerformGraphSelectionAction(target) else { return {} }
        let modeID = addModeID
        return { [weak self] in
            guard let self, self.addModeID == modeID, self.canPerformGraphSelectionAction(target) else { return }
            self.perform(acceptCommittedCancellation: true) { try await $0.performGraphSelectionAction(target: target) }
        }
    }

    func canvasInputCancellationAction() -> (@MainActor () -> Void)? {
        guard let source = acceptedDocumentSource, isAddingNodes || isMovingOrigin else { return nil }
        let sourceIdentity = source.documentIdentity
        let add = addModeID
        let tool = rotationInputContextID
        let origin = originDragToken
        return { [weak self] in
            guard let self, self.acceptedDocumentSource?.documentIdentity == sourceIdentity,
                self.addModeID == add, self.rotationInputContextID == tool, self.originDragToken == origin
            else { return }
            if self.isAddingNodes {
                self.cancelAddMode()
            } else if self.isMovingOrigin {
                self.cancelOriginDrag()
            }
        }
    }

    /// A replaced pointer surface cannot cancel a later Add activation.
    func canvasAddCancellationAction() -> @MainActor () -> Void {
        let modeID = addModeID
        return { [weak self] in
            guard let self, !self.stopped, self.isAddingNodes, self.addModeID == modeID else { return }
            self.cancelAddMode()
        }
    }

    func canPerformCanvasPartIsolation(_ target: CanvasPartIsolationTarget?) -> Bool {
        guard !stopped, !isWorking, !isAddingNodes, !isMovingOrigin, !referenceColorInteractionActive,
            let target, let snapshot
        else { return false }
        return target.isAvailable && target.isCurrent(in: snapshot)
    }

    func canvasPartIsolationAction(_ target: CanvasPartIsolationTarget?) -> @MainActor () -> Void {
        guard let target, canPerformCanvasPartIsolation(target) else { return {} }
        return { [weak self] in
            guard let self, self.canPerformCanvasPartIsolation(target) else { return }
            self.perform(acceptCommittedCancellation: true) { try await $0.setCanvasPartIsolation(target: target) }
        }
    }

    func canPerformInspectorAction(_ target: GraphInspectorActionTarget?) -> Bool {
        guard !stopped, !isWorking, let target, let snapshot else { return false }
        return target.isCurrent(in: snapshot)
    }
    func inspectorAction(_ target: GraphInspectorActionTarget?) -> @MainActor () -> Void {
        guard let target, canPerformInspectorAction(target) else { return {} }
        return { [weak self] in
            guard let self, self.canPerformInspectorAction(target) else { return }
            self.perform(
                commits: target.changesDocument, acceptCommittedCancellation: true,
                selectionOnly: !target.changesDocument
            ) { try await $0.performInspectorAction(target: target) }
        }
    }

    func connect(to id: String) {
        guard let selected = snapshot?.selectedID else { return }
        let command = DocumentCommand.joinNodes(id: Self.identifier(), from: selected, to: id)
        perform { try await $0.apply([command]) }
    }

    func deleteNode() {
        guard let id = snapshot?.selectedID else { return }
        perform { try await $0.apply([.removeNode(id: id)]) }
    }

    func deleteEdge(_ id: String) { perform { try await $0.apply([.removeEdge(id: id)]) } }

    private static func identifier() -> String { "{\(UUID().uuidString.lowercased())}" }

    func undo() {
        cancelAddMode()
        perform(reloadReferenceImage: true) { try await $0.undo() }
    }
    func redo() {
        cancelAddMode()
        perform(reloadReferenceImage: true) { try await $0.redo() }
    }

    /// The sheet waits for publication before dismissing; validation errors keep its draft available.
    func applyReferenceComposition(
        _ result: ReferenceCompositionResult, target: ReferenceCompositionTarget, setsOrigin: Bool
    ) async -> Bool {
        guard canSave else { return false }
        guard acceptedDocumentSource != nil else {
            errorMessage = Self.message(EditorError.staleReferenceComposition)
            return false
        }
        return await withCheckedContinuation { continuation in
            perform(
                reloadReferenceImage: true,
                completion: { continuation.resume(returning: $0) }
            ) { session in
                try await session.applyReferenceComposition(
                    png: result.png, origin: setsOrigin ? result.layout.origin : nil, target: target)
            }
        }
    }

    var fittedReferenceColorImage: CGImage? {
        guard let preparedReferenceColors, preparedReferenceColors.sourceID == referenceRequestID,
            preparedReferenceColors.canvas == referenceColorCanvas?.identity
        else { return nil }
        return preparedReferenceColors.result.displayImage
    }
    func fittedReferenceColorImage(in canvas: ReferenceColorCanvasIdentity) -> CGImage? {
        guard preparedReferenceColors?.canvas == canvas else { return nil }
        return fittedReferenceColorImage
    }
    var referenceColorDisplayAspect: Double? {
        guard let preparedReferenceColors, fittedReferenceColorImage != nil else { return nil }
        return Double(preparedReferenceColors.result.referenceSize.width)
            / Double(preparedReferenceColors.result.referenceSize.height)
    }
    private var hasColorizeAdmission: Bool {
        canSave && !isAddingNodes && !isMovingOrigin && !referenceColorInteractionActive
            && snapshot.map(GraphReferenceColorPlan.canColorize) == true
    }
    var canClearSelectionColors: Bool {
        hasColorizeAdmission && snapshot?.selectedNodes.contains(where: \.isEditable) == true
    }
    var canAutoColorSelection: Bool {
        guard hasColorizeAdmission, let snapshot, showsReferenceImage, !isLoadingReferenceImage,
            !isPreparingReferenceColors, !referenceColorInteractionActive, fittedReferenceColorImage != nil
        else { return false }
        if snapshot.selectedNodes.contains(where: \.isEditable) { return true }
        let parts = Dictionary(uniqueKeysWithValues: snapshot.parts.map { ($0.id, $0) })
        return snapshot.selectedEdges.contains { edge in
            guard let partID = edge.partID, let part = parts[partID] else { return true }
            return part.isEditable
        }
    }
    func setReferenceColorCanvasContext(projection: CanvasProjection, width: Double, height: Double) {
        let identity = ReferenceColorCanvasIdentity(projection: projection, width: width, height: height)
        guard identity.isValid else {
            clearReferenceColorCanvasContext()
            return
        }
        guard identity != referenceColorCanvas?.identity else { return }
        invalidateReferenceColors()
        referenceColorCanvas = (identity, projection)
        scheduleReferenceColors()
    }
    func clearReferenceColorCanvasContext() {
        invalidateReferenceColors()
        referenceColorCanvas = nil
    }
    func setReferenceColorInteractionActive(_ active: Bool) {
        guard active != referenceColorInteractionActive else { return }
        referenceColorInteractionActive = active
        referenceColorInteractionEpoch = UUID()
        if active { cancelReferenceColorCommit() }
    }
    private func cancelReferenceColorCommit() {
        if referenceColorOperationID == operationRequestID { operation?.cancel() }
    }
    private func invalidateReferenceColors() {
        cancelReferenceColorCommit()
        referenceColorPreparation?.cancel()
        referenceColorPreparationID = UUID()
        isPreparingReferenceColors = false
        preparedReferenceColors = nil
        referenceColorError = nil
        referenceColorNotice = nil
    }
    private func scheduleReferenceColors() {
        guard !stopped, showsReferenceImage, !isLoadingReferenceImage, referenceImageError == nil,
            let snapshot, snapshot.document.hasReferenceImage, let canvas = referenceColorCanvas
        else { return }
        referenceColorPreparation?.cancel()
        let requestID = UUID()
        referenceColorPreparationID = requestID
        let sourceID = referenceRequestID
        let documentID = snapshot.documentIdentity
        let service = referenceColorRaster
        isPreparingReferenceColors = true
        referenceColorError = nil
        referenceColorPreparation = Task { [weak self] in
            await Task.yield()  // Collapse same-turn geometry changes before entering bounded raster work.
            do {
                try Task.checkCancellation()
                let result = try await service.prepare(
                    document: snapshot.document, logicalHeight: canvas.identity.scale)
                try Task.checkCancellation()
                guard let self, !self.stopped, self.referenceColorPreparationID == requestID,
                    self.referenceRequestID == sourceID, self.snapshot?.documentIdentity == documentID,
                    self.referenceColorCanvas?.identity == canvas.identity, self.showsReferenceImage
                else { return }
                let layout = try ReferenceColorSamplingLayout(
                    referenceSize: result.referenceSize, projection: canvas.projection)
                self.preparedReferenceColors = .init(
                    sourceID: sourceID, canvas: canvas.identity, result: result, layout: layout)
                self.isPreparingReferenceColors = false
            } catch {
                guard let self, !Task.isCancelled, self.referenceColorPreparationID == requestID else { return }
                self.referenceColorError = Self.message(error)
                self.isPreparingReferenceColors = false
            }
        }
    }
    func referenceColorAction() -> @MainActor () -> Void {
        let target = snapshot.map(ReferenceColorTarget.init)
        let admitted = canAutoColorSelection
        let preparationID = referenceColorPreparationID
        let interaction = referenceColorInteractionEpoch
        let canvas = referenceColorCanvas?.identity
        let source = referenceRequestID
        let tool = rotationInputContextID
        let add = addModeID
        return { [weak self] in
            guard admitted, let self, let target, let snapshot = self.snapshot, target.isCurrent(in: snapshot),
                preparationID == self.referenceColorPreparationID, interaction == self.referenceColorInteractionEpoch,
                canvas == self.referenceColorCanvas?.identity,
                source == self.referenceRequestID,
                tool == self.rotationInputContextID, add == self.addModeID
            else { return }
            self.autoColorSelection()
        }
    }
    func clearSelectionColorsAction() -> @MainActor () -> Void {
        let target = snapshot.map(CanvasAdjustmentTarget.init)
        let admitted = canClearSelectionColors
        let interaction = referenceColorInteractionEpoch
        let tool = rotationInputContextID
        let add = addModeID
        return { [weak self] in
            guard admitted, let self, let target, let snapshot = self.snapshot, target.isCurrent(in: snapshot),
                self.canClearSelectionColors, interaction == self.referenceColorInteractionEpoch,
                tool == self.rotationInputContextID, add == self.addModeID
            else { return }
            self.referenceColorNotice = nil
            self.perform { try await $0.clearSelectedPartColors(target: target) }
        }
    }
    func clearSelectionColors() { clearSelectionColorsAction()() }
    func autoColorSelection() {
        guard canAutoColorSelection, let snapshot, let prepared = preparedReferenceColors else { return }
        let target = ReferenceColorTarget(snapshot: snapshot)
        let application = referenceColorApplying
        let documentID = snapshot.documentIdentity
        let token = UUID()
        referenceColorApplyToken = token
        perform(
            acceptCommittedCancellation: true,
            completion: { [weak self] _ in
                guard let self, self.referenceColorApplyToken == token else { return }
                self.referenceColorOperationID = nil
            },
            { [weak self] session in
                let receipt = try await application.apply(
                    raster: prepared.result.raster, layout: prepared.layout,
                    referencePNG: prepared.result.referencePNG, target: target, in: session)
                await self?.acceptReferenceColorReceipt(receipt, documentID: documentID, token: token)
                return receipt.snapshot
            }
        )
        referenceColorOperationID = operationRequestID
        referenceColorCommitTask = operation
    }
    private func acceptReferenceColorReceipt(_ receipt: ReferenceColorReceipt, documentID: UUID, token: UUID) {
        guard !stopped, snapshot?.documentIdentity == documentID, referenceColorApplyToken == token,
            referenceColorOperationID == operationRequestID
        else { return }
        referenceColorNotice =
            receipt.didChange
            ? "Auto Color changed \(receipt.changedComponentCount) part colors."
            : "No part colors changed."
        if receipt.skippedReadOnlyObjects > 0 {
            referenceColorNotice? += " Skipped \(receipt.skippedReadOnlyObjects) read-only objects."
        }
        if receipt.skippedOutsideObjects > 0 {
            referenceColorNotice? += " Skipped \(receipt.skippedOutsideObjects) objects outside the reference."
        }
    }

    func importReferenceImage(from url: URL) {
        let service = referenceImages
        perform(reloadReferenceImage: true) { session in
            let png = try await service.importImage(url: url)
            return try await session.apply([.setReferenceImagePNG(png)])
        }
    }

    func removeReferenceImage() {
        perform(reloadReferenceImage: true) { try await $0.apply([.setReferenceImagePNG(nil)]) }
    }

    func movePreviewCamera(_ action: MeshCameraCommand.Action) {
        guard canMovePreviewCamera else { return }
        previewCameraCommand = .init(action)
    }

    func fitPreviewCamera() {
        guard canMovePreviewCamera else { return }
        previewCameraCommand = nil
        canvasWheelZoom = .init()
        cameraReset += 1
    }

    func fit() {
        previewCameraCommand = nil
        canvasWheelZoom = .init()
        cancelOriginDrag()
        fitCanvas()
        cameraReset += 1
    }

    private func fitCanvas(preservingOriginMode: Bool = false) {
        guard !isAddingNodes else { return }
        cancelOriginDrag(preservingMode: preservingOriginMode)
        let aspect = showsReferenceImage ? referenceImage.map { Double($0.width) / Double($0.height) } : nil
        bounds = CanvasBounds(nodes: snapshot?.nodes ?? [], referenceImageAspectRatio: aspect, origin: snapshot?.origin)
    }

    func stop() {
        graphComponentRevealLookup = nil
        canvasAxisLockQueue = nil
        changeRigEdgeSelection(false)
        changeComponentBrowseGroup(nil)
        canvasGraphHoverCache = CanvasGraphHover.Cache()
        qtXMLFilePasteRequest = nil
        canvasProfileMotion = nil
        boneEdgeHover = nil
        previewCameraCommand = nil
        pendingComponentDrag = nil
        invalidateReferenceColors()
        referenceColorApplyToken = UUID()
        referenceColorOperationID = nil
        pendingWholePartPick = nil
        isSelectingGraph = false
        cancelAddMode(refit: false)
        changeAddPlacementDestination(.selection)
        authoringCatalog.stop()
        cancelAnimationQuery()
        cancelExport()
        cancelColorImagePreparation()
        operationRequestID = UUID()
        isWorking = false
        cancelOriginDrag()
        stopped = true
        graphWheelQueue = nil
        operation?.cancel()
        generation?.cancel()
        referenceGeneration?.cancel()
        clearPreview()
        onDocumentChanged = nil
        onEditingChanged?(false)
        onEditingChanged = nil
    }

    private func perform(
        commits: Bool = true, reloadReferenceImage: Bool = false, acceptCommittedCancellation: Bool = false,
        selectionOnly: Bool = false, preserveOriginMode: Bool = false, preservePartStateHover: Bool = false,
        completion: (@MainActor (Bool) -> Void)? = nil,
        _ action: @escaping @Sendable (EditorSession) async throws -> EditorSnapshot
    ) {
        guard canSave else {
            completion?(false)
            return
        }
        cancelColorImagePreparation()
        cancelOriginDrag(preservingMode: preserveOriginMode)
        let requestID = UUID()
        operationRequestID = requestID
        canvasPartStateHoverOperation = preservePartStateHover ? requestID : nil
        isSelectingGraph = selectionOnly
        isWorking = true
        operation = Task {
            var succeeded = false
            defer {
                if canvasPartStateHoverOperation == requestID { canvasPartStateHoverOperation = nil }
                if operationRequestID == requestID {
                    isWorking = false
                    isSelectingGraph = false
                }
                completion?(succeeded)
                if operationRequestID == requestID { drainWholePartPick() }
            }
            do {
                let next = try await action(session)
                guard !Task.isCancelled || acceptCommittedCancellation, !stopped, operationRequestID == requestID else {
                    return
                }
                if acceptCommittedCancellation && next.documentIdentity != snapshot?.documentIdentity { return }
                let changed = next.documentRevision != snapshot?.documentRevision
                let previousPreviewIdentity = snapshot?.previewIdentity
                // Visibility changes need fitting even when topology is unchanged; movements keep stable drag bounds.
                let countChanged = next.nodes.count != snapshot?.nodes.count
                let needsFit =
                    next.origin != snapshot?.origin
                    || !next.nodes.elementsEqual(snapshot?.nodes ?? []) {
                        $0.id == $1.id && $0.isVisible == $1.isVisible
                    }
                snapshot = next
                if countChanged && !isAddingNodes {
                    fit()
                } else if needsFit && !isAddingNodes {
                    fitCanvas(preservingOriginMode: preserveOriginMode)
                }
                errorMessage = nil
                if commits && changed {
                    onDocumentChanged?(next.document.encoded())
                    if previousPreviewIdentity?.geometry != next.previewIdentity.geometry {
                        generate(next)
                    } else if previousPreviewIdentity?.materials != next.previewIdentity.materials {
                        clearMaterials()
                        if mesh == nil || previewState.isStale {
                            generate(next, preservingFailure: true)
                        } else {
                            generateMaterials(next)
                        }
                    }
                    if reloadReferenceImage { refreshReferenceImage(next) }
                }
                succeeded = true
            } catch {
                if !Task.isCancelled, operationRequestID == requestID { errorMessage = Self.message(error) }
            }
        }
    }

    private func clearPreview() {
        clearMaterials()
        generation?.cancel()
        previewState.clear()
        previewCacheStatistics = nil
        previewSourceIssue = nil
        let previousScope = previewScopeID
        previewScopeID = UUID()
        Task { [preview] in
            do {
                try await preview.reset(scopeID: previousScope)
            } catch {
                Self.previewLogger.error(
                    "Preview cache reset for \(previousScope.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    private func generate(_ snapshot: EditorSnapshot, preservingFailure: Bool = false) {
        clearMaterials()
        generation?.cancel()
        renderError = nil
        guard snapshot.hasEnabledGeometry else {
            clearPreview()
            return
        }
        previewCacheStatistics = nil
        previewSourceIssue = nil
        let scopeID = previewScopeID
        let requestID = UUID()
        previewState.begin(requestID: requestID, preservingError: preservingFailure)
        generation = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let result = try await preview.generate(snapshot.document.encoded(), scopeID: scopeID)
                // Asset-only edits can advance document revision without changing geometry; request identity wins.
                guard !Task.isCancelled, !stopped, scopeID == previewScopeID,
                    self.snapshot?.previewIdentity.geometry == snapshot.previewIdentity.geometry,
                    previewState.isCurrent(requestID: requestID)
                else {
                    return
                }
                previewCacheStatistics = result.statistics
                previewSourceIssue = result.sourceIssue
                if let output = result.output {
                    previewState.succeed(output, requestID: requestID)
                    if let currentSnapshot = self.snapshot { generateMaterials(currentSnapshot) }
                } else {
                    previewState.succeedEmpty(requestID: requestID)
                }
            } catch {
                guard !Task.isCancelled, !stopped, scopeID == previewScopeID,
                    self.snapshot?.previewIdentity.geometry == snapshot.previewIdentity.geometry,
                    previewState.isCurrent(requestID: requestID)
                else { return }
                previewState.fail(Self.message(error), requestID: requestID)
            }
        }
    }

    private func clearMaterials() {
        renderedMaterialRevision = nil
        materialGeneration?.cancel()
        materialState.clear()
        materialRenderError = nil
    }

    func retryMaterials() {
        guard !stopped, !isWorking, !previewState.isGenerating, !previewState.isStale,
            mesh != nil, let snapshot
        else { return }
        generateMaterials(snapshot)
    }

    private func generateMaterials(_ snapshot: EditorSnapshot) {
        renderedMaterialRevision = nil
        materialGeneration?.cancel()
        materialRenderError = nil
        let requestID = UUID()
        let scopeID = previewScopeID
        materialState.begin(requestID: requestID)
        materialGeneration = Task { [materialPreparation] in
            do {
                let data = snapshot.document.encoded()
                let result = try await materialPreparation.load(data: data, options: .init())
                guard !Task.isCancelled, !stopped, scopeID == previewScopeID else { return }
                materialState.succeed(result, requestID: requestID)
            } catch {
                guard !Task.isCancelled, !stopped, scopeID == previewScopeID else { return }
                materialState.fail(error.localizedDescription, requestID: requestID)
            }
        }
    }

    func retryPreview() {
        guard !stopped, !isGenerating, let snapshot else { return }
        generate(snapshot)
    }

    private func refreshReferenceImage(_ snapshot: EditorSnapshot, forceFit: Bool = false) {
        referenceGeneration?.cancel()
        invalidateReferenceColors()
        let requestID = UUID()
        referenceRequestID = requestID
        referenceImageError = nil
        isLoadingReferenceImage = true
        let hadImage = referenceImage != nil
        if !snapshot.document.hasReferenceImage {
            referenceImage = nil
            if hadImage { fit() }
        }
        referenceGeneration = Task {
            do {
                let result = try await referenceImages.preview(document: snapshot.document)
                guard !Task.isCancelled, !stopped, referenceRequestID == requestID else { return }
                referenceImage = result.image
                isLoadingReferenceImage = false
                // Empty results only clear the cache; Load/removal already fitted their visible content.
                if result.image != nil && (result.changed || forceFit || !hadImage) { fit() }
                scheduleReferenceColors()
            } catch {
                guard !Task.isCancelled, !stopped, referenceRequestID == requestID else { return }
                referenceImage = nil
                referenceImageError = Self.message(error)
                isLoadingReferenceImage = false
                if hadImage { fit() }
            }
        }
    }

    static func message(_ error: Error) -> String {
        if error is ComponentWrapBindingError {
            return "The wrapping weights inspector changed. Choose the source again."
        }
        if error is ComponentSurfaceError { return "The wrapping finish inspector changed. Choose the edit again." }
        if error is ComponentPartRoleError { return "The component role selection changed. Choose the role again." }
        if case .inheritedContext(let id, let attribute) = error as? ComponentReparentError {
            return "Cannot move \(id) without changing inherited \(attribute). The source is unchanged."
        }
        if error is ComponentDeletionError {
            return "The component deletion target changed. Choose the components again."
        }
        if error is ComponentUngroupSelectionError {
            return "The component Ungroup target changed. Choose the components again."
        }
        if let ungroup = error as? ComponentUngroupError {
            switch ungroup {
            case .inheritedContext(let id, let attribute):
                return "Cannot ungroup \(id) without changing inherited \(attribute). The source is unchanged."
            case .textNamespaceContext(let id):
                return
                    "Cannot ungroup \(id) without changing the namespace context of its text. The source is unchanged."
            }
        }
        if error is ComponentMeshSelectionError {
            return "The component settings selection changed. Choose the edit again."
        }
        if let color = error as? ReferenceColorError {
            switch color {
            case .invalidRaster: return "The reference color raster has invalid pixel storage."
            case .invalidLayout: return "The reference color layout is not supported."
            case .unresolvableOwner(let id): return "The selected object's part ownership cannot be resolved: \(id)."
            case .ambiguousOwner(let id): return "The selected part has multiple component owners: \(id)."
            }
        }
        if let raster = error as? ReferenceColorRasterError {
            switch raster {
            case .missingReference: return "No reference image is available."
            case .invalidLimits: return "The reference sampling limits are invalid."
            case .fittedLimitExceeded: return "The fitted reference exceeds the sampling limit."
            case .unsupportedOrientation(let value): return "Unsupported reference orientation: \(value)."
            case .invalidLogicalHeight: return "The reference display size is invalid."
            case .unsupportedDisplayProfile: return "The reference color profile cannot be represented safely."
            case .incompatibleGrayPixels: return "The grayscale reference contains inconsistent channels."
            case .displayImageUnavailable: return "The fitted reference display image could not be created."
            }
        }
        if let image = error as? ReferenceImageError {
            switch image {
            case .invalidImage:
                return "The reference image could not be decoded. Its existing archive bytes remain preserved."
            case .unsupportedFormat: return "Choose a PNG, JPEG, BMP, GIF or TIFF reference image."
            case .imageTooLarge:
                return "Reference images are limited to 32 MiB, 8192 pixels per side and 16 megapixels."
            case .conversionFailed: return "The reference image could not be converted to PNG."
            case .fileReadFailed(let cause): return "The reference image could not be read: \(cause)"
            }
        }
        if let composition = error as? ReferenceCompositionError {
            switch composition {
            case .invalidDimensions: return "Use positive source dimensions within the reference-image limits."
            case .invalidCrop: return "Enter a nonempty crop fully inside the source image."
            case .emptyComposition: return "Import a Front or Side image before applying."
            case .outputTooLarge:
                return "This crop would produce a turnaround wider than 8192 pixels. Use a taller or narrower crop."
            }
        }
        if let document = error as? DocumentError {
            switch document {
            case .invalidArchive: return "This file is not a supported Dust3D 1.0 archive."
            case .invalidXML: return "The document contains invalid or unsupported XML."
            case .invalidOrigin: return "Enter finite origin coordinates within ±1,000,000."
            case .invalidReferenceImage: return "The reference image must contain PNG data."
            case .limitExceeded: return "The document or edit exceeds supported size or undo-history limits."
            case .missingNode(let id): return "Node \(id) is not present in this document."
            case .missingPart(let id): return "Part \(id) is not present in this document."
            case .invalidComponent:
                return "The document contains unsupported component tags or ambiguous identities/containers."
            case .invalidComponentStructure:
                return "Choose unique sibling components and an unlinked group destination without creating a cycle."
            case .invalidComponentWrapBinding: return "Choose an available body group, or Own Children."
            case .invalidComponentWrapping:
                return "Choose a group and wrapping values within the supported editing ranges."
            case .invalidComponentTargetSegments: return "Enter a whole target segment count from 0 to 100."
            case .invalidComponentStitchingScalar:
                return "Enter a depth from 0 to 2 or sharpness from 0 to 1 that the modeling engine can represent."
            case .invalidComponentSmoothing: return "Enter a finite smoothing cutoff from 0 to 180 degrees."
            case .invalidComponentColor: return "Enter #RRGGBB or #AARRGGBB, with alpha first."
            case .invalidComponentName: return "Use a single-line component name of at most 1024 UTF-8 bytes."
            case .missingComponent(let id): return "Component \(id) is not present in this document."
            case .invalidPartCutFace:
                return "Choose a preset or an existing profile part with an engine-compatible identity."
            case .invalidPartCutRotation:
                return "Enter a cut rotation from -1 to 1 that the modeling engine can represent."
            case .invalidPartHollowThickness: return "Enter a hollow thickness from 0 to 1."
            case .invalidPartMirrorRole: return "Mirrored copies require a procedural or imported model part."
            case .invalidPartMirrorOrigin: return "Set all three canvas origin coordinates before enabling Mirrored."
            case .invalidPartMaterial: return "Enter a material value within its supported range."
            case .invalidPartDeformation: return "Enter a scale from 0 to 2 that the modeling engine can represent."
            case .invalidPartName: return "Use a single-line part name of at most 1024 UTF-8 bytes."
            case .invalidBoneName:
                return "Use an exact bone name of at most 1024 UTF-8 bytes without controls or newlines."
            case .invalidNode: return "The document contains invalid node, part, or edge data."
            case .invalidNodeDeformation:
                return "Enter a positive node scale up to 1,000,000 that the mesh engine can represent."
            case .conflictingAsset(let name): return "Clipboard asset \(name) conflicts with this document."
            case .cyclicProfile: return "This edit would create a cyclic cut-face reference."
            case .transactionAlreadyOpen: return "An edit transaction is already in progress."
            case .noTransaction: return "No edit transaction is in progress."
            }
        }
        if let clipboard = error as? ClipboardError {
            switch clipboard {
            case .invalidPayload: return "The clipboard contains invalid Dust3D node data."
            case .unsupportedVersion: return "This clipboard data requires a newer Dust3D editor."
            }
        }
        if let pasteboard = error as? PasteboardError {
            switch pasteboard {
            case .writeFailed: return "The clipboard could not be written. No nodes were removed."
            }
        }
        if let editor = error as? EditorError {
            switch editor {
            case .notLoaded: return "Open a document before editing."
            case .readOnlyNode: return "This node belongs to a locked, hidden or disabled part."
            case .invalidReferenceColorSelection: return "Select at least one node before colorizing parts."
            case .staleReferenceColor:
                return "The reference color target changed. Choose the selection again and retry."
            case .staleReferenceComposition:
                return "The document or locks changed. Reopen the reference image composer."
            case .staleColorImageTarget: return "The document or selected component changed. Choose the image again."
            case .staleComponentMove: return "The document or component selection changed. Reset the parent chooser."
            case .staleOriginDrag: return "Origin drag cancelled because the document or constraints changed."
            case .stalePartGraphSelection: return "Part selection cancelled because the document changed."
            case .staleAddPlacement:
                return "Add placement cancelled because the document, selection or constraints changed."
            case .invalidAddPlacement: return "Move the add cursor to a valid canvas position."
            case .staleCanvasAdjustment:
                return "Canvas adjustment cancelled because the document, selection or constraints changed."
            case .staleNodeDrag: return "Node drag cancelled because the document, selection or constraints changed."
            case .staleAnimationTarget:
                return "The document changed. Select the animation again before editing."
            case .staleExport:
                return "Export cancelled because the document changed. Export the current document again."
            case .unavailableOrigin:
                return
                    "Set a complete supported document origin first. Unlock position axes to initialize an unavailable origin."
            case .invalidPivotSelection: return "Select exactly one node as the rotation pivot."
            case .invalidRotation: return "Enter a finite angle between −2147483647° and 2147483647°."
            case .invalidSpacingFactor: return "Selection spacing requires a finite factor."
            case .invalidScale: return "Enter a finite, positive scale factor. Use 1 to keep the current size."
            }
        }
        return error.localizedDescription
    }
}
