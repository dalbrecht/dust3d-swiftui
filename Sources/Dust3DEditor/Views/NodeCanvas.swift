import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct NodeCanvas: View {
    let store: EditorStore
    var profileLease: UUID? = nil
    var profileFocusRequest: CanvasProfileFocusRequest? = nil

    private var ownsProfile: Bool { store.ownsCanvasProfile(profileLease) }
    @State private var nodeDrag = NodeDragLifecycle()
    @State private var shiftedDrag: (token: UUID, plan: CanvasShiftDrag, positions: [String: NodePosition])?
    @State private var marquee: CanvasSelectionRectangle?

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
            let colorizeActions = GraphColorizeActions(store: store, admitsInput: { ownsProfile })
            let graphActions = GraphSelectionMenuActions(store: store, admitsInput: { ownsProfile })
            let cancelAddInput = store.canvasAddCancellationAction()
            let handlePrecisionKey = store.canvasPrecisionKeyHandler()
            let precisionKey: (CanvasPrecisionKeyInput) -> Bool = { ownsProfile && handlePrecisionKey($0) }
            let precisionActions = CanvasPrecisionActions(store: store)
            let nodes = store.snapshot?.nodes ?? []
            let boneHighlights = store.highlightedBoneEdgeIDs
            let graphHover = store.canvasGraphHover
            let addModeID = store.addModeID
            let shiftContext = store.canvasRotationContext
            let partContext = store.snapshot.map { PartGraphSelectionContext(snapshot: $0) }
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
                        guard ownsProfile, store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin
                        else { return }
                        store.selectMarquee(rectangle, projection: projection, mode: mode)
                    },
                    tap: { point, mode in
                        guard ownsProfile, store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin
                        else { return }
                        store.pickEdge(at: point, projection: projection, mode: mode)
                    },
                    rectangle: { marquee = $0 },
                    hover: { point in
                        guard ownsProfile, store.addModeID == addModeID else { return }
                        if store.isAddingNodes {
                            store.updateAddPointer(at: point, modeID: addModeID)
                        }
                        store.updateCanvasHover(at: point, projection: projection)
                    },
                    wheel: { input in
                        guard ownsProfile, store.addModeID == addModeID else { return false }
                        return store.handleCanvasWheel(input)
                    },
                    radiusKey: adjustRadius,
                    doubleClick: { point in
                        guard ownsProfile, store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin,
                            let partContext
                        else { return }
                        store.selectWholePart(at: point, projection: projection, context: partContext)
                    },
                    precisionKey: precisionKey, isAddingNodes: store.isAddingNodes,
                    addPress: { if ownsProfile { store.placeAddNode(at: $0, modeID: addModeID) } },
                    cancelInput: { if ownsProfile { cancelAddInput() } },
                    admitsPrimaryPress: admitPrimaryPress, profileFocusRequest: profileFocusRequest,
                    ownsProfile: { ownsProfile }
                )
                .id(
                    "\(store.plane.rawValue)-\(store.snapshot?.documentIdentity.uuidString ?? "empty")-\(geometry.size.width)-\(geometry.size.height)-\(addModeID)"
                )
                .accessibilityLabel("Marquee selection canvas")
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
                            let selected = store.snapshot?.selectedEdgeIDs.contains(edge.id) == true
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
                    NodeHandle(
                        node: node, projection: projection,
                        position: previewPosition(node, projection: projection),
                        selected: store.snapshot?.selectedIDs.contains(node.id) == true,
                        hovered: graphHover == .node(node.id),
                        enabled: store.canPickGraph && !store.isMovingOrigin && !store.isAddingNodes,
                        canDrag: !store.isWorking && node.isEditable,
                        canSelectWholePart: store.canPickGraph && node.partID != nil,
                        colorizeActions: colorizeActions, graphActions: graphActions, precisionKey: precisionKey,
                        precisionActions: precisionActions,
                        doubleClick: {
                            guard ownsProfile, store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin
                            else {
                                return
                            }
                            store.selectWholePart(.node(node.id), context: partContext)
                        },
                        select: {
                            if ownsProfile, store.addModeID == addModeID && !store.isAddingNodes {
                                store.select(node.id)
                            }
                        },
                        toggle: {
                            if ownsProfile, store.addModeID == addModeID && !store.isAddingNodes {
                                store.toggleSelection(node.id)
                            }
                        },
                        add: {
                            if ownsProfile, store.addModeID == addModeID && !store.isAddingNodes {
                                store.selectGraph(nodes: [node.id], edges: [], mode: .add)
                            }
                        },
                        subtract: {
                            if ownsProfile, store.addModeID == addModeID && !store.isAddingNodes {
                                store.selectGraph(nodes: [node.id], edges: [], mode: .subtract)
                            }
                        },
                        wheel: { input in
                            guard ownsProfile, store.addModeID == addModeID, !store.isAddingNodes else { return false }
                            store.setHoveredNode(node.id)
                            return store.handleCanvasWheel(input)
                        },
                        radiusKey: adjustRadius,
                        begin: { token in
                            guard ownsProfile, store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin
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
                            guard ownsProfile, store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin
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
                            guard ownsProfile, store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin
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
                            guard ownsProfile, store.canvasRotationContext == shiftContext,
                                store.addModeID == addModeID,
                                !store.isAddingNodes, !store.isMovingOrigin,
                                let snapshot = store.snapshot,
                                let plan = try? CanvasShiftDrag(
                                    anchorID: node.id, snapshot: snapshot, projection: projection)
                            else { return }
                            shiftedDrag = (token, plan, [:])
                            store.beginCanvasProfileMotion(token: token, lease: profileLease)
                        },
                        admitsPrimaryPress: admitPrimaryPress
                    )
                    .id(addModeID)
                    .allowsHitTesting(!store.isMovingOrigin && !store.isAddingNodes)
                }
                if let origin = store.originDragPosition ?? store.snapshot?.origin {
                    OriginHandle(store: store, origin: origin, projection: projection, profileLease: profileLease)
                        .allowsHitTesting(!store.isAddingNodes)
                }
                if nodes.isEmpty && store.referenceImage == nil {
                    VStack {
                        Spacer()
                        Text("Add a node from the Nodes menu or open a model.")
                            .font(.callout).foregroundStyle(.secondary).padding(24)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: referenceCanvas, initial: true) { _, _ in
                guard ownsProfile else { return }
                store.setReferenceColorCanvasContext(
                    projection: projection, width: geometry.size.width, height: geometry.size.height)
            }
            .onChange(of: nodeDrag.preview != nil || shiftedDrag != nil || marquee != nil) { _, active in
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
                if !store.isAddingNodes {
                    store.setCanvasContext(
                        projection: projection, width: geometry.size.width, height: geometry.size.height,
                        lease: profileLease)
                }
            }
            .onChange(of: store.isAddingNodes) { _, active in
                if ownsProfile { store.clearCanvasHover() }
                invalidateNodeDrag()
                marquee = nil
                if !active {
                    store.setCanvasContext(
                        projection: projection, width: geometry.size.width, height: geometry.size.height,
                        lease: profileLease)
                }
            }
            .onDisappear {
                invalidateNodeDrag()
                store.releaseCanvasProfile(lease: profileLease)
                marquee = nil
            }
            .contextMenu {
                GraphSelectionMenu(actions: graphActions)
                GraphColorizeMenu(actions: colorizeActions, contextual: true)
                CanvasPrecisionMenu(actions: precisionActions, contextual: true)
            }
            .coordinateSpace(name: "node-canvas")
            .clipped()
            .onChange(of: store.isMovingOrigin) { _, _ in
                invalidateNodeDrag()
                marquee = nil
                if ownsProfile { store.clearCanvasHover() }
            }
            .onChange(of: store.plane) { _, _ in
                invalidateNodeDrag()
                marquee = nil
                if ownsProfile { store.clearCanvasHover() }
            }
            .onChange(of: store.snapshot?.documentIdentity) { _, _ in
                invalidateNodeDrag()
                marquee = nil
                if ownsProfile { store.clearCanvasHover() }
            }
            .onChange(of: geometry.size) { _, _ in
                store.setCanvasContext(
                    projection: projection, width: geometry.size.width, height: geometry.size.height,
                    lease: profileLease)
                marquee = nil
                if ownsProfile { store.clearCanvasHover() }
                invalidateNodeDrag()
                if ownsProfile { store.cancelOriginDrag() }
            }
            .onChange(of: store.isWorking) { _, working in
                if working {
                    invalidateNodeDrag()
                    marquee = nil
                }
            }
        }
        .background(.background)
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
    let hovered: Bool
    let enabled: Bool
    let canDrag: Bool
    let canSelectWholePart: Bool
    let colorizeActions: GraphColorizeActions
    let graphActions: GraphSelectionMenuActions
    let precisionKey: (CanvasPrecisionKeyInput) -> Bool
    let precisionActions: CanvasPrecisionActions
    let doubleClick: () -> Void
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

    var body: some View {
        let point = projection.point(for: position)
        let marker = CanvasNodeMarkerGeometry(
            projectedDiameter: node.value.radius * projection.scale * 2, selected: selected, hovered: hovered)
        ZStack {
            Circle().stroke(
                selected || hovered ? Color.accentColor : .secondary.opacity(0.4),
                lineWidth: marker.outlineWidth
            )
            .frame(width: marker.outlineDiameter, height: marker.outlineDiameter)
            .allowsHitTesting(false)
            Circle().fill(selected ? Color.accentColor : (node.isEditable ? .primary : .secondary))
                .frame(width: CanvasNodeMarkerGeometry.centerDiameter, height: CanvasNodeMarkerGeometry.centerDiameter)
            NodePointerSurface(
                enabled: enabled, canDrag: canDrag, begin: begin, update: update, finish: finish,
                cancel: cancel,
                select: select, toggle: toggle, add: add, subtract: subtract, wheel: wheel, radiusKey: radiusKey,
                doubleClick: doubleClick,
                precisionKey: precisionKey,
                beginShiftDrag: beginShiftDrag, admitsPrimaryPress: admitsPrimaryPress
            ).frame(width: 36, height: 36)
        }
        .frame(width: 36, height: 36)
        .position(x: point.x, y: point.y)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select() }
        .accessibilityAction(named: Text("Select Whole Part")) { if canSelectWholePart { doubleClick() } }
        .contextMenu {
            if canSelectWholePart { Button("Select Whole Part", action: doubleClick) }
            GraphSelectionMenu(actions: graphActions)
            GraphColorizeMenu(actions: colorizeActions, contextual: true)
            CanvasPrecisionMenu(actions: precisionActions, contextual: true)
        }
        .accessibilityAction(named: Text("Add node to selection")) { add() }
        .accessibilityAction(named: Text("Remove node from selection")) {
            subtract()
        }
        .help(
            "\(node.title) · \(node.isEditable ? "Drag to move, Shift-drag to rotate or bend" : "Locked, hidden or disabled part")"
        )
    }
}
