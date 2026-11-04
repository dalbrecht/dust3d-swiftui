import Dust3DDocument

/// Qt's replay speed setting is linear in delay, from about three seconds to 50 ms.
package enum WorkflowReplaySpeed {
    package static let range = 1...20
    package static let initial = 11

    package static func intervalMilliseconds(for setting: Int) -> Int {
        let bounded = min(range.upperBound, max(range.lowerBound, setting))
        return 3150 - bounded * 155
    }
}

/// Reconstruct the source graph in component order without mutating the source document.
package struct WorkflowReplayPlan: Sendable {
    package enum Step: Equatable, Sendable {
        case referenceImage
        case node(id: String, incomingEdgeID: String?)
        case edge(id: String)
        case property(ReplayProperty)
    }

    package let steps: [Step]
    package let bounds: CanvasBounds
    private let graph: DocumentContents

    package func frame(after completedSteps: Int) -> (nodes: [DocumentNode], edges: [DocumentEdge]) {
        var nodes = Set<String>()
        var edges = Set<String>()
        for step in steps.prefix(max(0, completedSteps)) {
            switch step {
            case .node(let id, let incoming):
                nodes.insert(id)
                if let incoming { edges.insert(incoming) }
            case .edge(let id):
                edges.insert(id)
            case .referenceImage, .property: break
            }
        }
        return (graph.nodes.filter { nodes.contains($0.id) }, graph.edges.filter { edges.contains($0.id) })
    }


    package func showsReferenceImage(after completedSteps: Int) -> Bool {
        completedSteps > 0 && steps.first == .referenceImage
    }

    package func bounds(referenceImageAspectRatio: Double) -> CanvasBounds {
        CanvasBounds(nodes: graph.nodes, referenceImageAspectRatio: referenceImageAspectRatio, origin: graph.origin)
    }

    package func previewDocument(after completedSteps: Int, source: Dust3DDocument) throws -> Dust3DDocument {
        guard completedSteps < steps.count else { return source }
        let visible = frame(after: completedSteps)
        let pending = steps.dropFirst(max(0, completedSteps)).compactMap { step -> ReplayProperty? in
            guard case .property(let property) = step else { return nil }
            return property
        }
        let frame = try source.replayFrame(
            nodeIDs: Set(visible.nodes.map(\.id)), edgeIDs: Set(visible.edges.map(\.id)),
            pendingProperties: pending)
        return frame.hasReferenceImage && !showsReferenceImage(after: completedSteps)
            ? try frame.applying(.setReferenceImagePNG(nil)) : frame
    }

    package init(document: Dust3DDocument) throws {
        let graph = try document.editorContents()
        let components = try document.components()
        let nodesByPart = Dictionary(grouping: graph.nodes, by: \.partID)
        let nodes = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard nodes.count == graph.nodes.count else { throw DocumentError.invalidNode }
        var edgesByPart: [String?: [DocumentEdge]] = [:]
        var crossPartEdges: [DocumentEdge] = []
        for edge in graph.edges {
            let fromPart = nodes[edge.fromID]?.partID
            let toPart = nodes[edge.toID]?.partID
            if fromPart == toPart {
                edgesByPart[fromPart, default: []].append(edge)
            } else {
                crossPartEdges.append(edge)
            }
        }

        var visitedParts = Set<String?>()
        var steps: [Step] = document.hasReferenceImage ? [.referenceImage] : []
        steps.reserveCapacity(graph.nodes.count + graph.edges.count)
        let partOrder = components.compactMap(\.partID).map(Optional.some)
            + graph.parts.map { Optional($0.id) } + [nil]
        for part in partOrder where visitedParts.insert(part).inserted {
            Self.appendSteps(
                nodes: nodesByPart[part] ?? [], edges: edgesByPart[part] ?? [], to: &steps)
        }
        steps.append(contentsOf: crossPartEdges.map { .edge(id: $0.id) })
        steps.append(contentsOf: try document.replayProperties().map(Step.property))
        self.steps = steps
        self.graph = graph
        bounds = CanvasBounds(nodes: graph.nodes, origin: graph.origin)
    }

    private static func appendSteps(nodes: [DocumentNode], edges: [DocumentEdge], to steps: inout [Step]) {
        struct Arrival {
            let node: String
            let edge: String?
        }

        var adjacency: [String: [Arrival]] = [:]
        for edge in edges {
            adjacency[edge.fromID, default: []].append(Arrival(node: edge.toID, edge: edge.id))
            adjacency[edge.toID, default: []].append(Arrival(node: edge.fromID, edge: edge.id))
        }
        // A chain starts at its first stored endpoint. A loop has no endpoint.
        let endpoints = nodes.filter { adjacency[$0.id, default: []].count <= 1 }
        var visitedNodes = Set<String>()
        var traversedEdges = Set<String>()
        for node in endpoints + nodes where !visitedNodes.contains(node.id) {
            var pending = [Arrival(node: node.id, edge: nil)]
            while let arrival = pending.popLast() {
                guard visitedNodes.insert(arrival.node).inserted else { continue }
                steps.append(.node(id: arrival.node, incomingEdgeID: arrival.edge))
                if let edge = arrival.edge { traversedEdges.insert(edge) }
                pending.append(contentsOf: adjacency[arrival.node, default: []].reversed())
            }
        }
        for edge in edges where !traversedEdges.contains(edge.id) {
            steps.append(.edge(id: edge.id))
        }
    }
}
