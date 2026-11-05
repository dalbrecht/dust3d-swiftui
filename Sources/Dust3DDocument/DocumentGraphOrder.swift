import Foundation

/// Qt keeps incident edge vectors in live edit order, independently of serialized XML ordering.
/// This value travels with immutable document snapshots and is deliberately absent from the archive.
struct DocumentGraphOrder: Equatable, Sendable {
    var incident: [String: [String]] = [:]

    init(model: XMLDocument) {
        let edges = Self.edges(model).sorted {
            ($0.attribute(forName: "id")?.stringValue ?? "").utf8.lexicographicallyPrecedes(
                ($1.attribute(forName: "id")?.stringValue ?? "").utf8)
        }
        for edge in edges { append(edge) }
    }

    private static func edges(_ model: XMLDocument) -> [XMLElement] {
        model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge") ?? []
    }

    private mutating func append(_ edge: XMLElement) {
        guard let id = edge.attribute(forName: "id")?.stringValue else { return }
        for key in ["from", "to"] {
            if let node = edge.attribute(forName: key)?.stringValue { incident[node, default: []].append(id) }
        }
    }

    /// Generic graph edits preserve surviving slots and append newly connected edges in creation order.
    func reconciled(with model: XMLDocument) -> Self {
        var result = self
        var memberships: [String: Set<String>] = [:]
        let edges = Self.edges(model)
        for edge in edges {
            guard let id = edge.attribute(forName: "id")?.stringValue else { continue }
            for key in ["from", "to"] {
                if let node = edge.attribute(forName: key)?.stringValue { memberships[node, default: []].insert(id) }
            }
        }
        result.incident = result.incident.compactMapValues { list in list.isEmpty ? nil : list }
        for (node, list) in result.incident {
            let retained = list.filter { memberships[node]?.contains($0) == true }
            if retained.isEmpty { result.incident.removeValue(forKey: node) } else { result.incident[node] = retained }
        }
        var retained = result.incident.mapValues { Set($0) }
        for edge in edges {
            guard let id = edge.attribute(forName: "id")?.stringValue else { continue }
            for key in ["from", "to"] {
                if let node = edge.attribute(forName: key)?.stringValue,
                    retained[node, default: []].insert(id).inserted
                {
                    result.incident[node, default: []].append(id)
                }
            }
        }
        return result
    }

    // Conservative logical charge for retained strings, array slots and dictionary entries; not a physical heap bound.
    var historyByteCost: Int {
        incident.reduce(0) { total, entry in
            total + 64 + entry.key.utf8.count + entry.value.reduce(0) { $0 + 64 + $1.utf8.count }
        }
    }

    mutating func replace(_ old: String, with new: String, at node: String) throws {
        guard let index = incident[node]?.firstIndex(of: old) else { throw DocumentError.invalidNode }
        incident[node]?[index] = new
    }
}

/// Ordered, sequential Qt reductions mutate only a private XML tree and a value snapshot before publication.
enum NodeReduction {
    static func apply(
        _ selected: [String], model: XMLDocument, contents: DocumentContents,
        order: inout DocumentGraphOrder
    ) throws -> Bool {
        guard selected.count <= 10_000 else { throw DocumentError.limitExceeded }
        let nodes = Dictionary(uniqueKeysWithValues: contents.nodes.map { ($0.id, $0) })
        let root = model.rootElement()
        var nodeElements = Dictionary(
            uniqueKeysWithValues: (root?.elements(forName: "nodes").first?.elements(forName: "node") ?? []).compactMap {
                element in
                element.attribute(forName: "id")?.stringValue.map { ($0, element) }
            })
        var edges = Dictionary(
            uniqueKeysWithValues: (root?.elements(forName: "edges").first?.elements(forName: "edge") ?? []).compactMap {
                element in
                element.attribute(forName: "id")?.stringValue.map { ($0, element) }
            })
        func key(_ id: String) -> String {
            CutFaceLinks.canonicalID(id).map { String($0.dropFirst().dropLast()) } ?? id
        }
        guard Set(nodes.keys.map(key)).count == nodes.count, Set(edges.keys.map(key)).count == edges.count else {
            throw DocumentError.invalidNode
        }
        let ids = Set(selected).sorted { key($0).utf8.lexicographicallyPrecedes(key($1).utf8) }
        var changed = false
        for id in ids {
            guard nodeElements[id] != nil else { continue }
            let incident = order.incident[id] ?? []
            guard incident.count == 2 else { continue }
            guard incident[0] != incident[1], let first = edges[incident[0]], let second = edges[incident[1]],
                let node = nodes[id], node.isEditable, let part = node.partID
            else { throw DocumentError.invalidNode }
            func neighbor(_ edge: XMLElement) throws -> String {
                guard edge.attribute(forName: "partId")?.stringValue == part,
                    let from = edge.attribute(forName: "from")?.stringValue,
                    let to = edge.attribute(forName: "to")?.stringValue, from != to,
                    from == id || to == id
                else { throw DocumentError.invalidNode }
                let neighbor = from == id ? to : from
                guard let value = nodes[neighbor], value.isEditable, value.partID == part,
                    nodeElements[neighbor] != nil
                else { throw DocumentError.invalidNode }
                return neighbor
            }
            let firstNeighbor = try neighbor(first)
            let secondNeighbor = try neighbor(second)
            let alreadyConnected = order.incident[firstNeighbor, default: []].contains { edgeID in
                guard let edge = edges[edgeID] else { return false }
                return edge.attribute(forName: "from")?.stringValue == secondNeighbor
                    || edge.attribute(forName: "to")?.stringValue == secondNeighbor
            }
            guard firstNeighbor != secondNeighbor, !alreadyConnected else { throw DocumentError.invalidNode }
            try order.replace(incident[1], with: incident[0], at: secondNeighbor)
            for name in ["from", "to"] where first.attribute(forName: name)?.stringValue == id {
                first.attribute(forName: name)?.stringValue = secondNeighbor
            }
            nodeElements.removeValue(forKey: id)?.detach()
            edges.removeValue(forKey: incident[1])?.detach()
            order.incident.removeValue(forKey: id)
            changed = true
        }
        return changed
    }
}
