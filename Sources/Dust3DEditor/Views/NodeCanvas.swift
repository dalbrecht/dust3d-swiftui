import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct NodeCanvas: View {
    let store: EditorStore
    @State private var drag: SelectionDrag?

    var body: some View {
        GeometryReader { geometry in
            let projection = CanvasProjection(
                bounds: store.bounds, plane: store.plane,
                width: geometry.size.width, height: geometry.size.height)
            let nodes = store.snapshot?.nodes ?? []
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
                MarqueeSurface(enabled: !store.isWorking) { rectangle, additive in
                    let ids = projection.nodeIDs(in: rectangle, nodes: nodes)
                    store.select(additive ? ids.union(store.snapshot?.selectedIDs ?? []) : ids)
                } tap: { point in
                    if let edgeID = projection.edgeID(near: point, nodes: nodes, edges: store.snapshot?.edges ?? []) {
                        store.selectEdge(edgeID)
                    } else {
                        store.select(nil)
                    }
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
                            let selected = store.snapshot?.selectedEdgeID == edge.id
                            context.stroke(
                                path, with: .color(selected ? .accentColor : .secondary.opacity(0.5)),
                                lineWidth: selected ? 4 : 2)
                        }
                    }
                }
                .allowsHitTesting(false)
                ForEach(nodes.filter(\.isVisible)) { node in
                    NodeHandle(
                        node: node, projection: projection,
                        position: previewPosition(node, projection: projection),
                        selected: store.snapshot?.selectedIDs.contains(node.id) == true,
                        enabled: !store.isWorking,
                        select: { store.select(node.id) },
                        toggle: { store.toggleSelection(node.id) },
                        drag: { translation in
                            drag = SelectionDrag(
                                anchorID: node.id, translation: translation, revision: store.snapshot?.documentRevision)
                        },
                        move: { translation in
                            drag = nil
                            store.move(
                                id: node.id,
                                to: projection.moving(node.value.position, by: translation, locks: store.locks))
                        })
                }
                if nodes.isEmpty && store.referenceImage == nil {
                    ContentUnavailableView(
                        "Open a model to edit its nodes", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            .coordinateSpace(name: "node-canvas")
            .clipped()
            .onChange(of: store.isWorking) { _, working in if working { drag = nil } }
        }
        .background(.background)
    }
    private func previewPosition(_ node: DocumentNode, projection: CanvasProjection) -> NodePosition {
        guard let drag, drag.revision == store.snapshot?.documentRevision, node.isEditable else {
            return node.value.position
        }
        let ids = store.snapshot?.selectedIDs ?? []
        let participates = ids.contains(drag.anchorID) ? ids.contains(node.id) : drag.anchorID == node.id
        return participates
            ? projection.moving(node.value.position, by: drag.translation, locks: store.locks)
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
    let drag: (CanvasPoint) -> Void
    let move: (CanvasPoint) -> Void

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
            Color.clear.frame(width: 36, height: 36).contentShape(Circle())
        }
        .frame(width: 36, height: 36)
        .position(x: point.x, y: point.y)
        .onTapGesture { if enabled { select() } }
        .highPriorityGesture(TapGesture().modifiers(.command).onEnded { if enabled { toggle() } })
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("node-canvas"))
                .onChanged { value in
                    if enabled && node.isEditable {
                        drag(.init(x: value.translation.width, y: value.translation.height))
                    }
                }
                .onEnded { value in
                    if enabled && node.isEditable {
                        move(.init(x: value.translation.width, y: value.translation.height))
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select() }
        .help("\(node.title) · \(node.isEditable ? "Drag to move" : "Locked, hidden or disabled part")")
    }
}

private struct SelectionDrag {
    let anchorID: String
    let translation: CanvasPoint
    let revision: Int?
}

private struct MarqueeSurface: View {
    let enabled: Bool
    let select: (CanvasSelectionRectangle, Bool) -> Void
    let tap: (CanvasPoint) -> Void
    @GestureState private var rectangle: CanvasSelectionRectangle?

    var body: some View {
        Rectangle().fill(.clear).contentShape(Rectangle())
            .overlay {
                if let rectangle {
                    let frame = CGRect(
                        x: rectangle.minimum.x, y: rectangle.minimum.y,
                        width: rectangle.maximum.x - rectangle.minimum.x,
                        height: rectangle.maximum.y - rectangle.minimum.y)
                    Path { $0.addRect(frame) }.fill(Color.accentColor.opacity(0.12))
                    Path { $0.addRect(frame) }.stroke(
                        Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .onTapGesture(coordinateSpace: .named("node-canvas")) { point in
                if enabled { tap(.init(x: point.x, y: point.y)) }
            }
            .gesture(selectionGesture(additive: false))
            .highPriorityGesture(selectionGesture(additive: true).modifiers(.shift))
            .accessibilityLabel("Marquee selection canvas")
            .help(
                "Click an edge to inspect it. Drag empty canvas to select node centers. Shift-drag adds to the selection."
            )
    }

    private func selectionGesture(additive: Bool) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("node-canvas"))
            .updating($rectangle) { value, state, _ in
                if enabled { state = bounds(value) }
            }
            .onEnded { value in
                if enabled { select(bounds(value), additive) }
            }
    }

    private func bounds(_ value: DragGesture.Value) -> CanvasSelectionRectangle {
        .init(
            from: .init(x: value.startLocation.x, y: value.startLocation.y),
            to: .init(x: value.location.x, y: value.location.y))
    }
}
