import Foundation

/// Endpoint joins preserve unrelated XML; consuming target settings is an explicit graph operation.
enum PartJoining {
    static func apply(id: String, from: String, to: String, model: XMLDocument, contents: DocumentContents) throws {
        let nodes = Dictionary(uniqueKeysWithValues: contents.nodes.map { ($0.id, $0) })
        guard !id.isEmpty, from != to, contents.edges.count < 20_000,
            let source = nodes[from], let target = nodes[to], source.isEditable, target.isEditable,
            let sourcePart = source.partID, let targetPart = target.partID,
            !contents.edges.contains(where: {
                $0.id == id || ($0.fromID == from && $0.toID == to) || ($0.fromID == to && $0.toID == from)
            })
        else {
            throw DocumentError.invalidNode
        }
        var incident: [String: [DocumentEdge]] = [:]
        for edge in contents.edges {
            incident[edge.fromID, default: []].append(edge)
            incident[edge.toID, default: []].append(edge)
        }
        guard (incident[from]?.count ?? 0) < 2, (incident[to]?.count ?? 0) < 2 else { throw DocumentError.invalidNode }
        guard let root = model.rootElement(), let parts = root.elements(forName: "parts").first else {
            throw DocumentError.invalidXML
        }
        let profileParts = CutFaceLinks.index(
            parts.elements(forName: "part").compactMap { $0.attribute(forName: "id")?.stringValue })
        let nodeElements = root.elements(forName: "nodes").first?.elements(forName: "node") ?? []
        let edges: XMLElement
        if let existing = root.elements(forName: "edges").first {
            edges = existing
        } else {
            edges = XMLElement(name: "edges")
            root.addChild(edges)
        }
        let reversed = incident[from]?.first?.fromID == from
        if sourcePart != targetPart {
            let members = Set(contents.nodes.filter { $0.partID == targetPart }.map(\.id))
            let ordered = try chain(start: to, members: members, incident: incident)
            let rank = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })
            for edge in edges.elements(forName: "edge") {
                let a = edge.attribute(forName: "from")?.stringValue ?? ""
                let b = edge.attribute(forName: "to")?.stringValue ?? ""
                if let aRank = rank[a], let bRank = rank[b] {
                    let ascending = reversed ? aRank > bRank : aRank < bRank
                    set(edge, "from", ascending ? a : b)
                    set(edge, "to", ascending ? b : a)
                    set(edge, "partId", sourcePart)
                }
            }
            for node in nodeElements where members.contains(node.attribute(forName: "id")?.stringValue ?? "") {
                set(node, "partId", sourcePart)
            }
            for component in PartSplitting.componentElements(model)
            where component.attribute(forName: "linkDataType")?.stringValue == "partId"
                && component.attribute(forName: "linkData")?.stringValue == targetPart
            {
                if component.elements(forName: "component").isEmpty {
                    component.detach()
                } else {
                    component.removeAttribute(forName: "linkData")
                    component.removeAttribute(forName: "linkDataType")
                }
            }
            for part in parts.elements(forName: "part") where part.attribute(forName: "id")?.stringValue == targetPart {
                part.detach()
            }
            for element in parts.elements(forName: "part") + nodeElements
            where CutFaceLinks.target(element.attribute(forName: "cutFace")?.stringValue, in: profileParts)
                == targetPart
            {
                guard CutFaceLinks.canonicalID(sourcePart) != nil else { throw DocumentError.invalidNode }
                set(element, "cutFace", sourcePart)
            }
        }
        let edge = XMLElement(name: "edge")
        for (name, value) in [
            ("id", id), ("partId", sourcePart), ("from", reversed ? to : from), ("to", reversed ? from : to),
        ] {
            set(edge, name, value)
        }
        edges.addChild(edge)
        try validateConnectedPart(sourcePart, nodes: nodeElements, edges: edges.elements(forName: "edge"))
        try validateProfileLinks(parts: parts.elements(forName: "part"), nodes: nodeElements)
    }

    private static func chain(start: String, members: Set<String>, incident: [String: [DocumentEdge]]) throws
        -> [String]
    {
        var result: [String] = []
        var visited = Set<String>()
        var current: String? = start
        while let node = current {
            guard members.contains(node), visited.insert(node).inserted, (incident[node]?.count ?? 0) <= 2 else {
                throw DocumentError.invalidNode
            }
            result.append(node)
            let next = (incident[node] ?? []).map { $0.fromID == node ? $0.toID : $0.fromID }.filter {
                !visited.contains($0)
            }
            guard next.count <= 1 else { throw DocumentError.invalidNode }
            current = next.first
        }
        guard result.count == members.count else { throw DocumentError.invalidNode }
        return result
    }

    private static func validateConnectedPart(_ id: String, nodes: [XMLElement], edges: [XMLElement]) throws {
        let members = Set(
            nodes.filter { $0.attribute(forName: "partId")?.stringValue == id }.compactMap {
                $0.attribute(forName: "id")?.stringValue
            })
        var neighbors: [String: [String]] = [:]
        for edge in edges {
            let from = edge.attribute(forName: "from")?.stringValue ?? ""
            let to = edge.attribute(forName: "to")?.stringValue ?? ""
            if members.contains(from) || members.contains(to) {
                guard members.contains(from), members.contains(to) else { throw DocumentError.invalidNode }
                neighbors[from, default: []].append(to)
                neighbors[to, default: []].append(from)
            }
        }
        guard neighbors.values.allSatisfy({ $0.count <= 2 }) else { throw DocumentError.invalidNode }
        var pending = Array(members.prefix(1))
        var visited = Set(pending)
        var cursor = 0
        while cursor < pending.count {
            for neighbor in neighbors[pending[cursor]] ?? [] where visited.insert(neighbor).inserted {
                pending.append(neighbor)
            }
            cursor += 1
        }
        guard visited.count == members.count else { throw DocumentError.invalidNode }
    }

    static func validateProfileLinks(parts: [XMLElement], nodes: [XMLElement]) throws {
        let ids = Set(parts.compactMap { $0.attribute(forName: "id")?.stringValue })
        let profileParts = CutFaceLinks.index(Array(ids))
        var links: [String: [String]] = [:]
        for part in parts {
            if let id = part.attribute(forName: "id")?.stringValue,
                let target = CutFaceLinks.target(part.attribute(forName: "cutFace")?.stringValue, in: profileParts)
            {
                links[id, default: []].append(target)
            }
        }
        for node in nodes {
            if let id = node.attribute(forName: "partId")?.stringValue,
                let target = CutFaceLinks.target(node.attribute(forName: "cutFace")?.stringValue, in: profileParts)
            {
                links[id, default: []].append(target)
            }
        }
        var state: [String: Int] = [:]
        for id in ids {
            var pending = [(id, false)]
            while let (current, finishing) = pending.popLast() {
                if finishing {
                    state[current] = 2
                    continue
                }
                if state[current] == 2 { continue }
                guard state[current] != 1 else { throw DocumentError.cyclicProfile }
                state[current] = 1
                pending.append((current, true))
                pending.append(contentsOf: (links[current] ?? []).map { ($0, false) })
            }
        }
    }

    private static func set(_ element: XMLElement, _ name: String, _ value: String) {
        if let attribute = element.attribute(forName: name) {
            attribute.stringValue = value
        } else {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = name
            attribute.stringValue = value
            element.addAttribute(attribute)
        }
    }
}
