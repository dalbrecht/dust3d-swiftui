import Foundation

/// Caller-supplied identities for one edge in an atomic midpoint batch.
public struct EdgeMidpointInsertion: Sendable {
    public let originalEdgeID: String
    public let nodeID: String
    public let edgeID: String

    /// Retain `originalEdgeID` for the first segment and supply fresh midpoint/second-segment identities.
    public init(originalEdgeID: String, nodeID: String, edgeID: String) {
        self.originalEdgeID = originalEdgeID
        self.nodeID = nodeID
        self.edgeID = edgeID
    }
}

/// One graph/XML index and one validation pass serve the whole captured edge selection.
enum EdgeMidpoints {
    struct Source {
        let edge: DocumentEdge
        let element: XMLElement
        let partID: String
        let midpoint: EditableNode
    }

    static func sources(ids: [String], model: XMLDocument, contents: DocumentContents) throws -> [Source] {
        guard ids.count <= 10_000 - contents.nodes.count, ids.count <= 20_000 - contents.edges.count else {
            throw DocumentError.limitExceeded
        }
        guard Set(ids).count == ids.count else { throw DocumentError.invalidNode }
        let nodes = Dictionary(uniqueKeysWithValues: contents.nodes.map { ($0.id, $0) })
        let edges = Dictionary(uniqueKeysWithValues: contents.edges.map { ($0.id, $0) })
        let elements = Dictionary(
            uniqueKeysWithValues: (model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge")
                ?? []).compactMap { element in
                    element.attribute(forName: "id")?.stringValue.map { ($0, element) }
                })
        func key(_ id: String) -> String {
            CutFaceLinks.canonicalID(id).map { String($0.dropFirst().dropLast()) } ?? id
        }
        let ordered = ids.sorted {
            let first = key($0)
            let second = key($1)
            return first == second
                ? $0.utf8.lexicographicallyPrecedes($1.utf8) : first.utf8.lexicographicallyPrecedes(second.utf8)
        }
        return try ordered.map { id in
            guard let edge = edges[id], edge.fromID != edge.toID,
                let source = nodes[edge.fromID], source.isEditable,
                let target = nodes[edge.toID], target.isEditable,
                let partID = source.partID, target.partID == partID,
                let element = elements[id], element.attribute(forName: "partId")?.stringValue == partID
            else { throw DocumentError.invalidNode }
            let first = source.value
            let second = target.value
            let midpoint = EditableNode(
                position: .init(
                    x: first.position.x / 2 + second.position.x / 2,
                    y: first.position.y / 2 + second.position.y / 2,
                    z: first.position.z / 2 + second.position.z / 2), radius: first.radius / 2 + second.radius / 2)
            guard midpoint.isValid else { throw DocumentError.invalidNode }
            return Source(edge: edge, element: element, partID: partID, midpoint: midpoint)
        }
    }

    static func apply(
        _ requests: [EdgeMidpointInsertion], model: XMLDocument, contents: DocumentContents,
        order: inout DocumentGraphOrder
    ) throws {
        let sources = try sources(ids: requests.map(\.originalEdgeID), model: model, contents: contents)
        let fresh = requests.flatMap { [$0.nodeID, $0.edgeID] }
        let keys = fresh.map { CutFaceLinks.canonicalID($0) ?? $0 }
        let existing = Set(
            DocumentXML.semanticElements(model).compactMap { $0.attribute(forName: "id")?.stringValue }
                .map { CutFaceLinks.canonicalID($0) ?? $0 })
        guard
            fresh.allSatisfy({
                !$0.isEmpty && $0.utf8.count <= 128
                    && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            }),
            Set(keys).count == keys.count, existing.isDisjoint(with: keys)
        else { throw DocumentError.invalidNode }
        let byID = Dictionary(uniqueKeysWithValues: requests.map { ($0.originalEdgeID, $0) })
        var slots: [String: [String: Int]] = [:]
        for (node, incident) in order.incident {
            for (index, edge) in incident.enumerated() { slots[node, default: [:]][edge] = index }
        }
        // Validate every incident replacement before mutating even the private XML/order snapshot.
        for source in sources {
            guard slots[source.edge.toID]?[source.edge.id] != nil else { throw DocumentError.invalidNode }
        }
        guard let root = model.rootElement() else { throw DocumentError.invalidXML }
        func container(_ name: String) -> XMLElement {
            if let value = root.elements(forName: name).first { return value }
            let value = XMLElement(name: name)
            root.addChild(value)
            return value
        }
        func element(_ name: String, _ values: [(String, String)]) -> XMLElement {
            let result = XMLElement(name: name)
            for (name, value) in values {
                let attribute = XMLNode(kind: .attribute)
                attribute.name = name
                attribute.stringValue = value
                result.addAttribute(attribute)
            }
            return result
        }
        let nodes = container("nodes")
        let edges = container("edges")
        for source in sources {
            guard let request = byID[source.edge.id], let slot = slots[source.edge.toID]?[source.edge.id] else {
                throw DocumentError.invalidNode
            }
            let position = source.midpoint.position
            nodes.addChild(
                element(
                    "node",
                    [
                        ("id", request.nodeID), ("partId", source.partID),
                        ("x", String(position.x)), ("y", String(position.y)), ("z", String(position.z)),
                        ("radius", String(source.midpoint.radius)),
                    ]))
            order.incident[source.edge.toID]?[slot] = request.edgeID
            order.incident[request.nodeID] = [source.edge.id, request.edgeID]
            source.element.attribute(forName: "to")?.stringValue = request.nodeID
            var attributes = [
                ("id", request.edgeID), ("partId", source.partID), ("from", request.nodeID), ("to", source.edge.toID),
            ]
            for name in ["name", "boneName"] {
                if let value = source.element.attribute(forName: name)?.stringValue { attributes.append((name, value)) }
            }
            edges.addChild(element("edge", attributes))
        }
    }
}
