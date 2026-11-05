import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct NodeCanvas: View {
    let store: EditorStore
    @State private var nodeDrag = NodeDragLifecycle()
    @State private var marquee: CanvasSelectionRectangle?

    var body: some View {
        GeometryReader { geometry in
            let projection =
                store.frozenAddProjection
                ?? nodeDrag.displayProjection(
                    fallback: CanvasProjection(
                        bounds: store.bounds, plane: store.plane,
                        width: geometry.size.width, height: geometry.size.height))
            let nodes = store.snapshot?.nodes ?? []
            let addModeID = store.addModeID
            ZStack {
                if store.showsReferenceImage, let image = store.referenceImage {
                    let aspect = Double(image.width) / Double(image.height)
                    let center = projection.point(for: .init(x: aspect / 2, y: 0.5, z: aspect / 2))
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: aspect * projection.scale, height: projection.scale)
                        .position(x: center.x, y: center.y)
                        .opacity(store.referenceImageOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                CanvasPointerSurface(
                    enabled: !store.isWorking && !store.isMovingOrigin,
                    select: { rectangle, mode in
                        guard store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin else { return }
                        store.selectMarquee(rectangle, projection: projection, mode: mode)
                    },
                    tap: { point, mode in
                        guard store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin else { return }
                        store.pickEdge(at: point, projection: projection, mode: mode)
                    },
                    rectangle: { marquee = $0 },
                    hover: { point in
                        guard store.addModeID == addModeID else { return }
                        if store.isAddingNodes {
                            store.updateAddPointer(at: point, modeID: addModeID)
                        } else {
                            store.updateCanvasHover(at: point, projection: projection)
                        }
                    },
                    wheel: { input in
                        guard store.addModeID == addModeID else { return false }
                        return store.handleCanvasWheel(input)
                    },
                    radiusKey: adjustRadius,
                    isAddingNodes: store.isAddingNodes,
                    addPress: { store.placeAddNode(at: $0, modeID: addModeID) },
                    cancelInput: { if store.addModeID == addModeID { store.cancelAddMode() } }
                )
                .id(
                    "\(store.plane.rawValue)-\(store.snapshot?.documentIdentity.uuidString ?? "empty")-\(geometry.size.width)-\(geometry.size.height)-\(addModeID)"
                )
                .accessibilityLabel("Marquee selection canvas")
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
                            context.stroke(
                                path, with: .color(selected ? .accentColor : .secondary.opacity(0.5)),
                                lineWidth: selected ? 4 : 2)
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
                        enabled: !store.isWorking && !store.isMovingOrigin && !store.isAddingNodes,
                        select: { if store.addModeID == addModeID && !store.isAddingNodes { store.select(node.id) } },
                        toggle: {
                            if store.addModeID == addModeID && !store.isAddingNodes { store.toggleSelection(node.id) }
                        },
                        add: {
                            if store.addModeID == addModeID && !store.isAddingNodes {
                                store.selectGraph(nodes: [node.id], edges: [], mode: .add)
                            }
                        },
                        wheel: { input in
                            guard store.addModeID == addModeID, !store.isAddingNodes else { return false }
                            store.setHoveredNode(node.id)
                            return store.handleCanvasWheel(input)
                        },
                        radiusKey: adjustRadius,
                        begin: { token in
                            guard store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin else {
                                return
                            }
                            guard let snapshot = store.snapshot else { return }
                            try? nodeDrag.begin(
                                token: token, anchorID: node.id, snapshot: snapshot, projection: projection)
                        },
                        update: { token, translation in
                            guard store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin else {
                                return
                            }
                            guard let snapshot = store.snapshot else { return }
                            nodeDrag.update(token: token, snapshot: snapshot, translation: translation)
                        },
                        finish: { token, translation in
                            guard store.addModeID == addModeID, !store.isAddingNodes, !store.isMovingOrigin else {
                                return
                            }
                            guard let baseline = nodeDrag.finish(token: token) else { return }
                            store.commitNodeDrag(baseline, translation: translation)
                        },
                        cancel: { token in nodeDrag.cancel(token: token) }
                    )
                    .id(addModeID)
                    .allowsHitTesting(!store.isMovingOrigin && !store.isAddingNodes)
                }
                if let origin = store.originDragPosition ?? store.snapshot?.origin {
                    OriginHandle(store: store, origin: origin, projection: projection).allowsHitTesting(
                        !store.isAddingNodes)
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
            .onAppear {
                store.setCanvasContext(projection: projection, width: geometry.size.width, height: geometry.size.height)
            }
            .onChange(of: geometry.size.height) { _, _ in
                store.setCanvasContext(projection: projection, width: geometry.size.width, height: geometry.size.height)
            }
            .onChange(of: store.snapshot?.documentRevision) { _, _ in
                if !store.isAddingNodes {
                    store.setCanvasContext(
                        projection: projection, width: geometry.size.width, height: geometry.size.height)
                }
            }
            .onChange(of: store.isAddingNodes) { _, active in
                invalidateNodeDrag()
                marquee = nil
                if !active {
                    store.setCanvasContext(
                        projection: projection, width: geometry.size.width, height: geometry.size.height)
                }
            }
            .onDisappear {
                store.cancelAddMode()
                store.setCanvasHeight(0)
                store.clearCanvasHover()
                marquee = nil
            }
            .coordinateSpace(name: "node-canvas")
            .clipped()
            .onChange(of: store.isMovingOrigin) { _, _ in
                invalidateNodeDrag()
                marquee = nil
                store.clearCanvasHover()
            }
            .onChange(of: store.plane) { _, _ in
                invalidateNodeDrag()
                marquee = nil
                store.clearCanvasHover()
            }
            .onChange(of: store.snapshot?.documentIdentity) { _, _ in
                marquee = nil
                store.clearCanvasHover()
            }
            .onChange(of: geometry.size) { _, _ in
                store.setCanvasContext(projection: projection, width: geometry.size.width, height: geometry.size.height)
                marquee = nil
                store.clearCanvasHover()
                invalidateNodeDrag()
                store.cancelOriginDrag()
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
    private func adjustRadius(_ direction: Int) -> Bool {
        guard store.canAdjustRadiusInput else { return false }
        store.adjustSelectionRadius(direction: Double(direction))
        return true
    }

    private func invalidateNodeDrag() { nodeDrag.invalidate() }

    private func previewPosition(_ node: DocumentNode, projection: CanvasProjection) -> NodePosition {
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
    let enabled: Bool
    let select: () -> Void
    let toggle: () -> Void
    let add: () -> Void
    let wheel: (CanvasWheelInput) -> Bool
    let radiusKey: (Int) -> Bool
    let begin: (UUID) -> Void
    let update: (UUID, CanvasPoint) -> Void
    let finish: (UUID, CanvasPoint) -> Void
    let cancel: (UUID) -> Void

    var body: some View {
        let point = projection.point(for: position)
        ZStack {
            Circle().stroke(selected ? Color.accentColor : .secondary.opacity(0.4), lineWidth: selected ? 2 : 1)
                .frame(
                    width: max(8, min(node.value.radius * projection.scale * 2, 600)),
                    height: max(8, min(node.value.radius * projection.scale * 2, 600))
                )
                .allowsHitTesting(false)
            Circle().fill(selected ? Color.accentColor : (node.isEditable ? .primary : .secondary))
                .frame(width: 12, height: 12)
            NodePointerSurface(
                enabled: enabled, canDrag: node.isEditable, begin: begin, update: update, finish: finish,
                cancel: cancel,
                select: select, toggle: toggle, add: add, wheel: wheel, radiusKey: radiusKey
            ).frame(width: 36, height: 36)
        }
        .frame(width: 36, height: 36)
        .position(x: point.x, y: point.y)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select() }
        .accessibilityAction(named: Text("Add node to selection")) { add() }
        .accessibilityAction(named: Text("Remove node from selection")) {
            if selected { toggle() }
        }
        .help("\(node.title) · \(node.isEditable ? "Drag to move" : "Locked, hidden or disabled part")")
    }
}
