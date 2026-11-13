import Dust3DDocument
import Foundation

/// Frozen graph and press intent used by both drag feedback and the eventual selection transaction.
package struct CanvasLassoPickPlan: Sendable {
    package typealias Picks = (nodes: Set<String>, edges: Set<String>)

    package let mode: GraphSelectionMode
    private let projection: CanvasProjection
    private let nodes: [DocumentNode]
    private let edges: [DocumentEdge]
    private let selected: Picks
    private let includesNodes: Bool

    package init(
        projection: CanvasProjection, nodes: [DocumentNode], edges: [DocumentEdge],
        selected: Picks, mode: GraphSelectionMode, includesNodes: Bool
    ) {
        self.projection = projection
        self.nodes = nodes
        self.edges = edges
        self.selected = selected
        self.mode = mode
        self.includesNodes = includesNodes
    }

    package func hits(in lasso: CanvasLasso) -> Picks {
        (
            includesNodes ? projection.nodeIDs(in: lasso, nodes: nodes) : [],
            projection.edgeIDs(in: lasso, nodes: nodes, edges: edges, selectedEdgeIDs: selected.edges)
        )
    }

    package func preview(in lasso: CanvasLasso) -> Picks {
        let hits = hits(in: lasso)
        switch mode {
        case .replace: return hits
        case .add:
            return (selected.nodes.union(hits.nodes), selected.edges.union(hits.edges))
        case .toggle:
            return (selected.nodes.symmetricDifference(hits.nodes), selected.edges.symmetricDifference(hits.edges))
        case .subtract:
            return (Self.subtract(hits.nodes, from: selected.nodes), Self.subtract(hits.edges, from: selected.edges))
        }
    }

    private static func subtract(_ hits: Set<String>, from selected: Set<String>) -> Set<String> {
        let exactHits = Set(hits.map { Data($0.utf8) })
        return selected.filter { !exactHits.contains(Data($0.utf8)) }
    }
}
