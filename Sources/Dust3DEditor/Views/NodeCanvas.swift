import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct NodeCanvas: View {
    let store: EditorStore
    var profileLease: UUID? = nil
    var profileFocusRequest: CanvasProfileFocusRequest? = nil
    var switchProfile: ((CanvasProfileFocusRequest) -> Bool)? = nil
    var focusControl: CanvasProfileFocusControl? = nil
    var previewCamera: EditorPreviewCameraActions? = nil
    var openDocument: @MainActor () -> Void = { NSDocumentController.shared.openDocument(nil) }

    private var ownsProfile: Bool { store.ownsCanvasProfile(profileLease) }
    @State private var nodeDrag = NodeDragLifecycle()
    @State private var shiftedDrag: (token: UUID, plan: CanvasShiftDrag, positions: [String: NodePosition])?
    @State private var marquee: CanvasSelectionRectangle?
    @State private var addModeFocus: (document: UUID, mode: UUID, request: CanvasProfileFocusRequest)?
    @State private var lasso = CanvasLassoFeedback()

    static func selectionAccessibilityLabel(usesLasso: Bool, selectsRigEdges: Bool) -> String {
        if usesLasso {
            return selectsRigEdges ? "Bone assignment lasso selection canvas" : "Lasso selection canvas"
        }
        return selectsRigEdges ? "Bone assignment edge selection canvas" : "Marquee selection canvas"
    }

    var body: some View {
        GeometryReader { geometry in
            let projection =
                store.frozenAddProjection
                ?? shiftedDrag?.plan.projection
                ?? nodeDrag.displayProjection(
                    fallback: CanvasProjection(
                        bounds: store.bounds, plane: store.plane,
                        width: geometry.size.width, height: geometry.size.height))
            let referenceCanvas = ReferenceColorCanvasIdentity(
                projection: projection, width: geometry.size.width, height: geometry.size.height)
            let selectionEpoch = store.rigEdgeSelectionEpoch
            let admitsInput: @MainActor () -> Bool = {
                store.admitsCanvasSelectionInput(epoch: selectionEpoch, lease: profileLease)
            }
            let admitsNodeInput = { admitsInput() && !store.isSelectingRigEdges }
            let colorizeActions = GraphColorizeActions(store: store, admitsInput: admitsInput)
            let graphActions = GraphSelectionMenuActions(store: store, admitsInput: admitsInput)
            let cancelAddInput = store.canvasAddCancellationAction()
            let handlePrecisionKey = store.canvasPrecisionKeyHandler()
            let zoomPreview = store.canvasPreviewWheelAction(lease: profileLease, camera: previewCamera)
            let handleAxisLockKey = store.canvasAxisLockKeyHandler(profileLease: profileLease)
            let handlePartStateKey = store.canvasPartStateKeyHandler(profileLease: profileLease)
            let precisionKey: (CanvasPrecisionKeyInput) -> Bool = {
                admitsInput() && (handleAxisLockKey($0) || handlePartStateKey($0) || handlePrecisionKey($0))
            }
            let precisionActions = CanvasPrecisionActions(store: store)
            let quarterTurns = OrthogonalQuarterTurnActions(store: store, profileLease: profileLease)
            let nodes = store.snapshot?.nodes ?? []
            let boneHighlights = store.highlightedBoneEdgeIDs
            let lassoPicks = lasso.picks
            let graphHover = lasso.path == nil && !lasso.isCommitting ? store.canvasGraphHover : nil
            let addModeID = store.addModeID
            let wheelDocument = store.snapshot?.documentIdentity
            let documentID = store.snapshot?.documentIdentity
            let handleAddModeKey = store.canvasAddModeKeyHandler(profileLease: profileLease)
            let addModeKey: CanvasAddModeKey.Handler = { key, request in
                guard admitsInput(), handleAddModeKey(key) else { return false }
                if let request, let documentID {
                    addModeFocus = (documentID, store.addModeID, request)
                }
                return true
            }
            let modeFocus =
                addModeFocus?.document == documentID && addModeFocus?.mode == addModeID ? addModeFocus?.request : nil
            let shiftContext = store.canvasRotationContext
            let partContext = store.snapshot.map { PartGraphSelectionContext(snapshot: $0) }
            let focusTarget = profileLease.flatMap { lease in
                store.snapshot.map { CanvasProfileFocusTarget(documentIdentity: $0.documentIdentity, lease: lease) }
            }
            let nodeSelectionTarget = store.canvasNodeSelectionTarget(profileLease: profileLease)
            let partIDs = Set(store.snapshot?.parts.map(\.id) ?? [])
            ZStack {
                if store.showsReferenceImage,
                    let image = store.fittedReferenceColorImage(in: referenceCanvas) ?? store.referenceImage
                {
                    let aspect = store.referenceColorDisplayAspect ?? Double(image.width) / Double(image.height)
                    let center = projection.point(for: .init(x: aspect / 2, y: 0.5, z: aspect / 2))
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: aspect * projection.scale, height: projection.scale)
                        .position(x: center.x, y: center.y)
                        .opacity(store.referenceImageOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                CanvasPointerSurface(
                    enabled: store.canPickGraph && !store.isMovingOrigin,
                    select: { rectangle, mode in
                        guard admitsInput(), store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin
                        else { return }
                        store.selectMarquee(rectangle, projection: projection, mode: mode)
                    },
                    tap: { point, mode in
                        guard admitsInput(), store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin
                        else { return }
                        store.pickCanvasGraph(at: point, projection: projection, mode: mode, lease: profileLease)
                    },
                    rectangle: { region in
                        guard admitsInput() else { return }
                        marquee = region
                        if region == nil { lasso.clear() }
                    },
                    hover: { point in
                        guard admitsInput(), store.addModeID == addModeID else { return }
                        if store.isAddingNodes {
                            store.updateAddPointer(at: point, modeID: addModeID)
                        }
                        store.updateCanvasHover(at: point, projection: projection)
                    },
                    wheel: { input in
                        guard admitsInput(), store.addModeID == addModeID,
                            wheelDocument == store.snapshot?.documentIdentity
                        else { return false }
                        return store.handleCanvasWheel(input, profileLease: profileLease)
                    },
                    wheelWhileDisabled: { store.canRouteGraphWheelWhileWorking },
                    unhandledWheel: store.canvasWheelZoomEnabled
                        ? { input in
                            guard admitsInput(), nodeDrag.preview == nil, shiftedDrag == nil, marquee == nil
                            else { return false }
                            return zoomPreview(input)
                        } : nil,
                    radiusKey: { admitsInput() && adjustRadius($0) },
                    doubleClick: { point, mode in
                        guard admitsInput(), store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin,
                            let partContext
                        else { return }
                        store.selectWholePart(
                            at: point, projection: projection, context: partContext,
                            onBlank: mode == .toggle ? openDocument : nil)
                    },
                    lassoCanvas: store.canvasUsesLasso ? referenceCanvas : nil,
                    lassoSelection: { mode in
                        guard admitsInput(), store.addModeID == addModeID else { return nil }
                        return store.lassoInteraction(
                            projection: projection, canvas: referenceCanvas, lease: profileLease, mode: mode)
                    },
                    lassoPreview: { if admitsInput() { lasso.update($0) } },
                    lassoFinish: { sample in
                        if admitsInput() {
                            lasso.finish(sample)
                        } else {
                            lasso.clear()
                        }
                    },
                    precisionKey: precisionKey, tracksHoverWhileDisabled: store.tracksPartStateHoverWhileWorking,
                    isAddingNodes: store.isAddingNodes,
                    addPress: { if admitsInput() { store.placeAddNode(at: $0, modeID: addModeID) } },
                    cancelInput: { if admitsInput() { cancelAddInput() } },
                    admitsPrimaryPress: { admitsInput() && admitPrimaryPress($0) },
                    profileFocusRequest: modeFocus ?? profileFocusRequest,
                    ownsProfile: {
                        ownsProfile && store.snapshot?.documentIdentity == documentID && store.addModeID == addModeID
                    }, switchProfile: switchProfile,
                    focusControl: focusControl, focusTarget: focusTarget, addModeKey: addModeKey
                )
                .id(
                    "\(store.plane.rawValue)-\(store.snapshot?.documentIdentity.uuidString ?? "empty")-\(geometry.size.width)-\(geometry.size.height)-\(addModeID)"
                )
                .id(selectionEpoch)
                .accessibilityLabel(
                    Self.selectionAccessibilityLabel(
                        usesLasso: store.canvasUsesLasso, selectsRigEdges: store.isSelectingRigEdges)
                )
                .help("Drag to select. Shift adds, Command toggles, and Command-Option removes hit nodes and edges.")
                if let marquee {
                    let frame = CGRect(
                        x: marquee.minimum.x, y: marquee.minimum.y,
                        width: marquee.maximum.x - marquee.minimum.x, height: marquee.maximum.y - marquee.minimum.y)
                    Path { $0.addRect(frame) }.fill(Color.accentColor.opacity(0.12)).allowsHitTesting(false)
                    Path { $0.addRect(frame) }.stroke(
                        Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    ).allowsHitTesting(false)
                }
                if let path = lasso.path {
                    let shape = lassoPath(path)
                    shape.fill(Color.accentColor.opacity(0.12), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false).accessibilityHidden(true)
                    shape.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                Canvas { context, _ in
                    let positions = Dictionary(
                        uniqueKeysWithValues: nodes.filter(\.isVisible).map {
                            ($0.id, projection.point(for: previewPosition($0, projection: projection)))
                        })
                    for edge in store.snapshot?.edges ?? [] {
                        if let from = positions[edge.fromID], let to = positions[edge.toID] {
                            var path = Path()
                            path.move(to: CGPoint(x: from.x, y: from.y))
                            path.addLine(to: CGPoint(x: to.x, y: to.y))
                            let selected =
                                lassoPicks?.edges.contains(edge.id)
                                ?? (store.snapshot?.selectedEdgeIDs.contains(edge.id) == true)
                            let highlighted = boneHighlights.contains(edge.id)
                            let hovered = graphHover == .edge(edge.id)
                            if highlighted {
                                context.stroke(path, with: .color(.accentColor.opacity(0.25)), lineWidth: 8)
                            }
                            context.stroke(
                                path,
                                with: .color(
                                    selected || highlighted || hovered ? .accentColor : .secondary.opacity(0.5)),
                                style: StrokeStyle(
                                    lineWidth: hovered ? 5 : (selected ? 4 : 2),
                                    dash: highlighted && !selected && !hovered ? [5, 3] : []))
                        }
                    }
                }
                .allowsHitTesting(false)
                if let ghost = store.addGhostPoint {
                    if let anchor = store.addAnchorPosition {
                        let start = projection.point(for: anchor)
                        Path { path in
                            path.move(to: .init(x: start.x, y: start.y))
                            path.addLine(to: .init(x: ghost.x, y: ghost.y))
                        }.stroke(Color.accentColor.opacity(0.65), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .allowsHitTesting(false)
                    }
                    Circle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: store.addGhostDisplayDiameter, height: store.addGhostDisplayDiameter)
                        .position(x: ghost.x, y: ghost.y).allowsHitTesting(false)
                        .accessibilityLabel("Add node preview")
                }
                ForEach(nodes.filter(\.isVisible)) { node in
                    let revealOwningComponent: (@MainActor () -> Void)? = {
                        guard admitsNodeInput(),
                            let reveal = store.revealOwningComponentAction(
                                .node(node.id), context: partContext, profileLease: profileLease)
                        else { return nil }
                        return { if admitsNodeInput() { reveal() } }
                    }()
                    let activate: (CanvasNodeSelectionAction) -> Void = {
                        store.activateCanvasNode(node.id, action: $0, target: nodeSelectionTarget)
                    }
                    NodeHandle(
                        node: node, projection: projection,
                        position: previewPosition(node, projection: projection),
                        selected: store.snapshot?.selectedIDs.contains(node.id) == true,
                        previewSelected: lassoPicks?.nodes.contains(node.id),
                        hovered: !store.isSelectingRigEdges && graphHover == .node(node.id),
                        enabled: nodeSelectionTarget != nil,
                        canDrag: !store.isWorking && node.isEditable,
                        canSelectWholePart: nodeSelectionTarget != nil
                            && node.partID.map { !$0.isEmpty && partIDs.contains($0) } == true,
                        colorizeActions: colorizeActions, graphActions: graphActions, precisionKey: precisionKey,
                        precisionActions: precisionActions, quarterTurns: quarterTurns,
                        revealOwningComponent: revealOwningComponent,
                        doubleClick: { activate(.wholePart) },
                        selectFromPointer: { activate(.pointerReplace) },
                        select: { activate(.selection(.replace)) },
                        toggle: { activate(.selection(.toggle)) },
                        add: { activate(.selection(.add)) },
                        subtract: { activate(.selection(.subtract)) },
                        wheel: { input in
                            guard admitsNodeInput(), store.addModeID == addModeID, !store.isAddingNodes,
                                wheelDocument == store.snapshot?.documentIdentity
                            else {
                                return false
                            }
                            store.setHoveredNode(node.id, projection: projection)
                            return store.handleCanvasWheel(input, profileLease: profileLease)
                        },
                        radiusKey: { admitsNodeInput() && adjustRadius($0) },
                        begin: { token in
                            guard admitsNodeInput(), store.addModeID == addModeID, !store.isAddingNodes,
                                !store.isMovingOrigin
                            else {
                                return
                            }
                            guard let snapshot = store.snapshot else { return }
                            if (try? nodeDrag.begin(
                                token: token, anchorID: node.id, snapshot: snapshot, projection: projection)) != nil
                            {
                                store.beginCanvasProfileMotion(token: token, lease: profileLease)
                            }
                        },
                        update: { token, translation in
                            guard admitsNodeInput(), store.addModeID == addModeID, !store.isAddingNodes,
                                !store.isMovingOrigin
                            else {
                                return
                            }
                            guard let snapshot = store.snapshot else { return }
                            if let drag = shiftedDrag, drag.token == token {
                                guard store.canvasRotationContext == shiftContext,
                                    drag.plan.isCurrent(in: snapshot)
                                else {
                                    shiftedDrag = nil
                                    store.clearCanvasProfileMotion(token: token, lease: profileLease)
                                    return
                                }
                                let updates = (try? drag.plan.updates(by: translation)) ?? []
                                let positions = Dictionary(
                                    uniqueKeysWithValues: updates.map { ($0.id, $0.value.position) })
                                shiftedDrag?.positions = positions
                                store.updateCanvasProfileMotion(.shifted(positions), token: token, lease: profileLease)
                            } else {
                                nodeDrag.update(token: token, snapshot: snapshot, translation: translation)
                                if let preview = nodeDrag.preview {
                                    store.updateCanvasProfileMotion(
                                        .ordinary(preview), token: token, lease: profileLease)
                                } else {
                                    store.clearCanvasProfileMotion(token: token, lease: profileLease)
                                }
                            }
                        },
                        finish: { token, translation in
                            guard admitsNodeInput(), store.addModeID == addModeID, !store.isAddingNodes,
                                !store.isMovingOrigin
                            else {
                                return
                            }
                            store.clearCanvasProfileMotion(token: token, lease: profileLease)
                            if let drag = shiftedDrag, drag.token == token {
                                shiftedDrag = nil
                                guard store.canvasRotationContext == shiftContext else { return }
                                store.commitCanvasShiftDrag(drag.plan, translation: translation)
                                return
                            }
                            guard let baseline = nodeDrag.finish(token: token) else { return }
                            store.commitNodeDrag(baseline, translation: translation)
                        },
                        cancel: { token in
                            store.clearCanvasProfileMotion(token: token, lease: profileLease)
                            if shiftedDrag?.token == token { shiftedDrag = nil }
                            nodeDrag.cancel(token: token)
                        },
                        beginShiftDrag: { token in
                            guard admitsNodeInput(), store.canvasRotationContext == shiftContext,
                                store.addModeID == addModeID,
                                !store.isAddingNodes, !store.isMovingOrigin,
                                let snapshot = store.snapshot,
                                let plan = try? CanvasShiftDrag(
                                    anchorID: node.id, snapshot: snapshot, projection: projection)
                            else { return }
                            shiftedDrag = (token, plan, [:])
                            store.beginCanvasProfileMotion(token: token, lease: profileLease)
                        },
                        admitsPrimaryPress: { admitsNodeInput() && admitPrimaryPress($0) },
                        switchProfile: switchProfile, addModeKey: addModeKey
                    )
                    .id(addModeID)
                    .id(selectionEpoch)
                    .allowsHitTesting(!store.isMovingOrigin && !store.isAddingNodes && !store.isSelectingRigEdges)
                    .accessibilityHidden(store.isSelectingRigEdges)
                }
                if let origin = store.originDragPosition ?? store.snapshot?.origin {
                    OriginHandle(store: store, origin: origin, projection: projection, profileLease: profileLease)
                        .allowsHitTesting(!store.isAddingNodes && !store.isSelectingRigEdges)
                }
            }
            .onChange(of: referenceCanvas, initial: true) { _, _ in
                guard ownsProfile else { return }
                lasso.clear()
                store.setReferenceColorCanvasContext(
                    projection: projection, width: geometry.size.width, height: geometry.size.height)
            }
            .onChange(of: nodeDrag.preview != nil || shiftedDrag != nil || marquee != nil || lasso.path != nil) {
                _, active in
                guard ownsProfile else { return }
                store.setReferenceColorInteractionActive(active)
            }
            .onAppear {
                store.setCanvasContext(
                    projection: projection, width: geometry.size.width, height: geometry.size.height,
                    lease: profileLease)
            }
            .onChange(of: geometry.size.height) { _, _ in
                store.setCanvasContext(
                    projection: projection, width: geometry.size.width, height: geometry.size.height,
                    lease: profileLease)
            }
            .onChange(of: store.snapshot?.documentRevision) { _, _ in
                lasso.clear()
                if !store.isAddingNodes {
                    store.setCanvasContext(
                        projection: projection, width: geometry.size.width, height: geometry.size.height,
                        lease: profileLease)
                }
            }
            .onChange(of: store.snapshot?.selectionRevision) { _, _ in lasso.clear() }
            .onChange(of: store.snapshot?.constraintRevision) { _, _ in lasso.clear() }
            .onChange(of: store.canvasUsesLasso) { _, _ in
                clearSelectionRegion()
            }
            .onChange(of: store.isAddingNodes) { _, active in
                if ownsProfile { store.clearCanvasHover() }
                invalidateNodeDrag()
                clearSelectionRegion()
                if !active {
                    store.setCanvasContext(
                        projection: projection, width: geometry.size.width, height: geometry.size.height,
                        lease: profileLease)
                }
            }
            .onDisappear {
                invalidateNodeDrag()
                store.releaseCanvasProfile(lease: profileLease)
                clearSelectionRegion()
            }
            .contextMenu {
                if let reveal = store.canvasHoverRevealAction(profileLease: profileLease) {
                    Button("Reveal Owning Component") { if admitsInput() { reveal() } }
                }
                if let select = store.canvasHoverWholePartAction(profileLease: profileLease) {
                    Button("Select Whole Part") { if admitsInput() { select() } }
                }
                GraphSelectionMenu(actions: graphActions)
                GraphColorizeMenu(actions: colorizeActions, contextual: true)
                OrthogonalQuarterTurnMenu(actions: quarterTurns, contextual: true)
                CanvasPrecisionMenu(actions: precisionActions, contextual: true)
            }
            .coordinateSpace(name: "node-canvas")
            .clipped()
            .onChange(of: store.rigEdgeSelectionEpoch) { _, _ in
                invalidateNodeDrag()
                clearSelectionRegion()
            }
            .onChange(of: store.isMovingOrigin) { _, _ in
                invalidateNodeDrag()
                clearSelectionRegion()
                if ownsProfile { store.clearCanvasHover() }
            }
            .onChange(of: store.plane) { _, _ in
                invalidateNodeDrag()
                clearSelectionRegion()
                if ownsProfile { store.clearCanvasHover() }
            }
            .onChange(of: store.snapshot?.documentIdentity) { _, _ in
                invalidateNodeDrag()
                clearSelectionRegion()
                if ownsProfile { store.clearCanvasHover() }
            }
            .onChange(of: geometry.size) { _, _ in
                store.setCanvasContext(
                    projection: projection, width: geometry.size.width, height: geometry.size.height,
                    lease: profileLease)
                clearSelectionRegion()
                if ownsProfile { store.clearCanvasHover() }
                invalidateNodeDrag()
                if ownsProfile { store.cancelOriginDrag() }
            }
            .onChange(of: store.isWorking) { _, working in
                if working {
                    invalidateNodeDrag()
                    marquee = nil
                    if !lasso.isCommitting { lasso.clear() }
                }
            }
        }
        .background(.background)
    }
    private func clearSelectionRegion() {
        marquee = nil
        lasso.clear()
    }

    private func lassoPath(_ lasso: CanvasLasso) -> Path {
        if lasso.points.count < 3, let bounds = lasso.bounds {
            return Path(
                CGRect(
                    x: bounds.minimum.x, y: bounds.minimum.y,
                    width: bounds.maximum.x - bounds.minimum.x, height: bounds.maximum.y - bounds.minimum.y))
        }
        return Path { path in
            path.addLines(lasso.points.map { CGPoint(x: $0.x, y: $0.y) })
            path.closeSubpath()
        }
    }

    private func admitPrimaryPress(_ clickCount: Int) -> Bool {
        store.admitsCanvasPrimaryPress(clickCount: clickCount, lease: profileLease)
    }

    private func adjustRadius(_ direction: Int) -> Bool {
        guard ownsProfile, store.canAdjustRadiusInput else { return false }
        store.adjustSelectionRadius(direction: Double(direction))
        return true
    }

    private func invalidateNodeDrag() {
        store.clearCanvasProfileMotion(lease: profileLease)
        nodeDrag.invalidate()
        shiftedDrag = nil
    }

    private func previewPosition(_ node: DocumentNode, projection: CanvasProjection) -> NodePosition {
        if let drag = shiftedDrag, let snapshot = store.snapshot, drag.plan.isCurrent(in: snapshot),
            let position = drag.positions[node.id]
        {
            return position
        }
        guard let drag = nodeDrag.preview, let snapshot = store.snapshot, drag.baseline.isCurrent(in: snapshot),
            node.isEditable
        else {
            return node.value.position
        }
        let participates = drag.baseline.includes(node.id)
        return participates
            ? drag.baseline.position(of: node.value.position, by: drag.translation)
            : node.value.position
    }

}

private struct NodeHandle: View {
    let node: DocumentNode
    let projection: CanvasProjection
    let position: NodePosition
    let selected: Bool
    var previewSelected: Bool? = nil
    let hovered: Bool
    let enabled: Bool
    let canDrag: Bool
    let canSelectWholePart: Bool
    let colorizeActions: GraphColorizeActions
    let graphActions: GraphSelectionMenuActions
    let precisionKey: (CanvasPrecisionKeyInput) -> Bool
    let precisionActions: CanvasPrecisionActions
    let quarterTurns: OrthogonalQuarterTurnActions
    let revealOwningComponent: (@MainActor () -> Void)?
    let doubleClick: () -> Void
    let selectFromPointer: () -> Void
    let select: () -> Void
    let toggle: () -> Void
    let add: () -> Void
    let subtract: () -> Void
    let wheel: (CanvasWheelInput) -> Bool
    let radiusKey: (Int) -> Bool
    let begin: (UUID) -> Void
    let update: (UUID, CanvasPoint) -> Void
    let finish: (UUID, CanvasPoint) -> Void
    let cancel: (UUID) -> Void
    let beginShiftDrag: (UUID) -> Void
    let admitsPrimaryPress: (Int) -> Bool
    let switchProfile: ((CanvasProfileFocusRequest) -> Bool)?
    let addModeKey: CanvasAddModeKey.Handler?

    var body: some View {
        let point = projection.point(for: position)
        let markerSelected = previewSelected ?? selected
        let marker = CanvasNodeMarkerGeometry(
            projectedDiameter: node.value.radius * projection.scale * 2, selected: markerSelected, hovered: hovered)
        ZStack {
            Circle().stroke(
                markerSelected || hovered ? Color.accentColor : .secondary.opacity(0.4),
                lineWidth: marker.outlineWidth
            )
            .frame(width: marker.outlineDiameter, height: marker.outlineDiameter)
            .allowsHitTesting(false)
            Circle().fill(markerSelected ? Color.accentColor : (node.isEditable ? .primary : .secondary))
                .frame(width: CanvasNodeMarkerGeometry.centerDiameter, height: CanvasNodeMarkerGeometry.centerDiameter)
            NodePointerSurface(
                enabled: enabled, canDrag: canDrag, begin: begin, update: update, finish: finish,
                cancel: cancel,
                select: selectFromPointer, toggle: toggle, add: add, subtract: subtract, wheel: wheel,
                radiusKey: radiusKey,
                doubleClick: doubleClick,
                precisionKey: precisionKey,
                beginShiftDrag: beginShiftDrag, admitsPrimaryPress: admitsPrimaryPress,
                switchProfile: switchProfile, addModeKey: addModeKey
            ).frame(width: 36, height: 36)
        }
        .frame(width: 36, height: 36)
        .position(x: point.x, y: point.y)
        .accessibilityRepresentation {
            if enabled {
                Button(node.title, action: select)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityActions {
                        if canSelectWholePart { Button("Select Whole Part", action: doubleClick) }
                        if let reveal = revealOwningComponent {
                            Button("Reveal Owning Component", action: reveal)
                        }
                        Button("Add node to selection", action: add)
                        Button("Remove node from selection", action: subtract)
                    }
            } else {
                Text(node.title).accessibilityValue(selected ? "Selected" : "Not selected")
            }
        }
        .contextMenu {
            if let reveal = revealOwningComponent {
                Button("Reveal Owning Component", action: reveal)
            }
            if canSelectWholePart { Button("Select Whole Part", action: doubleClick) }
            GraphSelectionMenu(actions: graphActions)
            GraphColorizeMenu(actions: colorizeActions, contextual: true)
            OrthogonalQuarterTurnMenu(actions: quarterTurns, contextual: true)
            CanvasPrecisionMenu(actions: precisionActions, contextual: true)
        }
        .help(
            "\(node.title) · \(node.isEditable ? "Drag to move, Shift-drag to rotate or bend" : "Locked, hidden or disabled part")"
        )
    }
}
