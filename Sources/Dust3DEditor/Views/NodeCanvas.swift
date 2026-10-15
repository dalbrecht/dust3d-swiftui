import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct NodeCanvas: View {
    let store: EditorStore

    var body: some View {
        GeometryReader { geometry in
            let projection = CanvasProjection(
                bounds: store.bounds, plane: store.plane,
                width: geometry.size.width, height: geometry.size.height)
            let nodes = store.snapshot?.nodes ?? []
            ZStack {
                Canvas { context, _ in
                    let positions = Dictionary(
                        uniqueKeysWithValues: nodes.filter(\.isVisible).map {
                            ($0.id, projection.point(for: $0.value.position))
                        })
                    for edge in store.snapshot?.edges ?? [] {
                        if let from = positions[edge.fromID], let to = positions[edge.toID] {
                            var path = Path()
                            path.move(to: CGPoint(x: from.x, y: from.y))
                            path.addLine(to: CGPoint(x: to.x, y: to.y))
                            context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 2)
                        }
                    }
                }
                ForEach(nodes.filter(\.isVisible)) { node in
                    NodeHandle(
                        node: node, projection: projection,
                        selected: store.snapshot?.selectedID == node.id,
                        enabled: !store.isWorking,
                        select: { store.select(node.id) },
                        move: { position in store.edit(id: node.id, position: position, radius: node.value.radius) })
                }
                if nodes.isEmpty {
                    ContentUnavailableView(
                        "Open a model to edit its nodes", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            .clipped()
        }
        .background(.background)
    }
}

private struct NodeHandle: View {
    let node: DocumentNode
    let projection: CanvasProjection
    let selected: Bool
    let enabled: Bool
    let select: () -> Void
    let move: (NodePosition) -> Void
    @GestureState private var translation = CGSize.zero

    var body: some View {
        let point = projection.point(for: node.value.position)
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
        .position(x: point.x + translation.width, y: point.y + translation.height)
        .onTapGesture { if enabled { select() } }
        .gesture(
            DragGesture(minimumDistance: 3)
                .updating($translation) { value, state, _ in
                    if enabled && node.isEditable { state = value.translation }
                }
                .onEnded { value in
                    if enabled && node.isEditable {
                        move(
                            projection.moving(
                                node.value.position,
                                by: CanvasPoint(x: value.translation.width, y: value.translation.height)))
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select() }
        .help("\(node.title) · \(node.isEditable ? "Drag to move" : "Locked or hidden part")")
    }
}
