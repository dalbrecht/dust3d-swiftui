import Dust3DEditorModel
import SwiftUI

/// Displays the graph and the active pane’s motion preview in the inactive profile.
struct CanvasProfileCompanion: View {
    let store: EditorStore
    let plane: EditingPlane

    var body: some View {
        let snapshot = store.snapshot
        let bounds = store.bounds
        let motion = store.canvasProfileMotion
        let graphHover = store.canvasGraphHover
        let origin = store.originDragPosition ?? snapshot?.origin
        let isMovingOrigin = store.isMovingOrigin
        let nodes = snapshot?.nodes.filter(\.isVisible) ?? []
        Canvas { context, size in
            let projection = CanvasProjection(bounds: bounds, plane: plane, width: size.width, height: size.height)
            let points = Dictionary(
                uniqueKeysWithValues: nodes.map { node in
                    let position = snapshot.flatMap { motion?.position(of: node, in: $0) } ?? node.value.position
                    let point = projection.point(for: position)
                    return (node.id, CGPoint(x: point.x, y: point.y))
                })
            for edge in snapshot?.edges ?? [] {
                guard let from = points[edge.fromID], let to = points[edge.toID] else { continue }
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                let selected = snapshot?.selectedEdgeIDs.contains(edge.id) == true
                let hovered = graphHover == .edge(edge.id)
                context.stroke(
                    path, with: .color(selected || hovered ? .accentColor : .secondary.opacity(0.5)),
                    lineWidth: hovered ? 5 : (selected ? 4 : 2))
            }
            for node in nodes {
                guard let point = points[node.id] else { continue }
                let selected = snapshot?.selectedIDs.contains(node.id) == true
                let hovered = graphHover == .node(node.id)
                let diameter = max(8, min(node.value.radius * projection.scale * 2, 600))
                context.stroke(
                    circle(at: point, diameter: diameter),
                    with: .color(selected || hovered ? .accentColor : .secondary.opacity(0.4)),
                    lineWidth: hovered ? 3 : (selected ? 2 : 1))
                context.fill(
                    circle(at: point, diameter: 12),
                    with: .color(selected ? .accentColor : (node.isEditable ? .primary : .secondary)))
            }
            if let origin {
                let point = projection.point(for: origin)
                context.draw(
                    Text(Image(systemName: "scope")).font(.title3)
                        .foregroundColor(isMovingOrigin ? .accentColor : .secondary),
                    at: CGPoint(x: point.x, y: point.y))
            }
        }
        .background(.background)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func circle(at point: CGPoint, diameter: Double) -> Path {
        Path(
            ellipseIn: CGRect(
                x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter))
    }
}
