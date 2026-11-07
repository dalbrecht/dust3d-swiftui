import Dust3DEditorModel
import SwiftUI

/// Displays the committed graph in the inactive profile.
struct CanvasProfileCompanion: View {
    let store: EditorStore
    let plane: EditingPlane

    var body: some View {
        let snapshot = store.snapshot
        let bounds = store.bounds
        let nodes = snapshot?.nodes.filter(\.isVisible) ?? []
        Canvas { context, size in
            let projection = CanvasProjection(bounds: bounds, plane: plane, width: size.width, height: size.height)
            let points = Dictionary(
                uniqueKeysWithValues: nodes.map { node in
                    let point = projection.point(for: node.value.position)
                    return (node.id, CGPoint(x: point.x, y: point.y))
                })
            for edge in snapshot?.edges ?? [] {
                guard let from = points[edge.fromID], let to = points[edge.toID] else { continue }
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                let selected = snapshot?.selectedEdgeIDs.contains(edge.id) == true
                context.stroke(
                    path, with: .color(selected ? .accentColor : .secondary.opacity(0.5)),
                    lineWidth: selected ? 4 : 2)
            }
            for node in nodes {
                guard let point = points[node.id] else { continue }
                let selected = snapshot?.selectedIDs.contains(node.id) == true
                let diameter = max(8, min(node.value.radius * projection.scale * 2, 600))
                context.stroke(
                    circle(at: point, diameter: diameter),
                    with: .color(selected ? .accentColor : .secondary.opacity(0.4)), lineWidth: selected ? 2 : 1)
                context.fill(
                    circle(at: point, diameter: 12),
                    with: .color(selected ? .accentColor : (node.isEditable ? .primary : .secondary)))
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
