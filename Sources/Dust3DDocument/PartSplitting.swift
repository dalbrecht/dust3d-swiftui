import Foundation

/// Fresh identifiers (at most 128 UTF-8 bytes each) for one additional connected group.
/// Component IDs follow the original component-reference order reported by requirement discovery.
public struct PartSplitIdentity: Sendable {
    public let partID: String
    public let componentIDs: [String]
    public init(partID: String, componentIDs: [String]) {
        self.partID = partID
        self.componentIDs = componentIDs
    }
}

/// Bounded identity requirements for a disconnected part, before any mutation or UUID allocation.
public struct PartSplitRequirement: Sendable {
    public let partID: String
    public let additionalPartCount: Int
    public let componentsPerPart: Int
}

/// XML mutation stays outside pure editor state. Caller publishes only the fully validated archive.
enum PartSplitting {
    static func requirements(model: XMLDocument, contents: DocumentContents, partIDs: Set<String>) throws
        -> [PartSplitRequirement]
    {
        let groups = try connectedGroups(contents: contents, partIDs: partIDs)
        let parts = model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part") ?? []
        let components = componentElements(model)
        let readOnlyParts = Set(contents.nodes.filter { !$0.isEditable }.compactMap(\.partID))
        let referencesByPart = Dictionary(
            grouping: components.filter {
                $0.attribute(forName: "linkDataType")?.stringValue == "partId"
            }, by: { $0.attribute(forName: "linkData")?.stringValue ?? "" })
        let existing = Set(parts.compactMap { $0.attribute(forName: "id")?.stringValue })
        guard partIDs.isSubset(of: existing) else { throw DocumentError.invalidNode }
        var result: [PartSplitRequirement] = []
        for part in parts {
            guard let id = part.attribute(forName: "id")?.stringValue, let selectedGroups = groups[id],
                selectedGroups.count > 1
            else { continue }
            guard !readOnlyParts.contains(id) else {
                throw DocumentError.invalidNode
            }
            let references = referencesByPart[id] ?? []
            let ids = references.compactMap { $0.attribute(forName: "id")?.stringValue }
            guard ids.count == references.count, ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else {
                throw DocumentError.invalidNode
            }
            result.append(
                .init(partID: id, additionalPartCount: selectedGroups.count - 1, componentsPerPart: references.count))
        }
        let additionalParts = result.reduce(0) { $0 + $1.additionalPartCount }
        let additionalComponents = result.reduce(0) { $0 + $1.additionalPartCount * $1.componentsPerPart }
        guard parts.count + additionalParts <= 10_000, components.count + additionalComponents <= 10_000 else {
            throw DocumentError.limitExceeded
        }
        // Bound copied metadata before allocating identities or large XML subtrees.
        let placeholder = "{00000000-0000-4000-8000-000000000000}"
        var projectedBytes = model.xmlData(options: [.nodePreserveAll]).count
        let partsByID = Dictionary(
            uniqueKeysWithValues: parts.compactMap { part -> (String, XMLElement)? in
                part.attribute(forName: "id")?.stringValue.map { ($0, part) }
            })
        for requirement in result {
            if let part = partsByID[requirement.partID], let copy = part.copy() as? XMLElement {
                set(copy, name: "id", value: placeholder)
                var bytes = copy.xmlString(options: [.nodePreserveAll]).utf8.count
                for reference in referencesByPart[requirement.partID] ?? [] {
                    let copy = try styleCopy(reference)
                    set(copy, name: "id", value: placeholder)
                    set(copy, name: "linkData", value: placeholder)
                    bytes += copy.xmlString(options: [.nodePreserveAll]).utf8.count
                }
                projectedBytes += bytes * requirement.additionalPartCount
            }
        }
        guard projectedBytes <= 16 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        return result
    }

    static func apply(id: String, identities: [PartSplitIdentity], model: XMLDocument, contents: DocumentContents)
        throws -> Bool
    {
        let plan = try requirements(model: model, contents: contents, partIDs: [id]).first
        guard identities.count == (plan?.additionalPartCount ?? 0) else { throw DocumentError.invalidNode }
        guard let plan else { return false }
        guard identities.allSatisfy({ $0.componentIDs.count == plan.componentsPerPart }) else {
            throw DocumentError.invalidNode
        }
        let identifiers = identities.flatMap { [$0.partID] + $0.componentIDs }
        let existing = Set(
            try model.nodes(forXPath: "//*[@id]").compactMap {
                ($0 as? XMLElement)?.attribute(forName: "id")?.stringValue
            })
        guard identifiers.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
            Set(identifiers).count == identifiers.count,
            existing.isDisjoint(with: identifiers)
        else { throw DocumentError.invalidNode }
        let groups = try connectedGroups(contents: contents, partIDs: [id])[id] ?? []
        guard let parts = model.rootElement()?.elements(forName: "parts").first,
            let part = parts.elements(forName: "part").first(where: { $0.attribute(forName: "id")?.stringValue == id })
        else {
            throw DocumentError.invalidXML
        }
        let references = componentElements(model).filter { referencesPart($0, id: id) }
        var anchors = references
        let nodes = model.rootElement()?.elements(forName: "nodes").first?.elements(forName: "node") ?? []
        let nodeElements = Dictionary(
            uniqueKeysWithValues: nodes.compactMap { element -> (String, XMLElement)? in
                element.attribute(forName: "id")?.stringValue.map { ($0, element) }
            })
        let edges = model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge") ?? []
        let edgesByFrom = Dictionary(grouping: edges, by: { $0.attribute(forName: "from")?.stringValue ?? "" })
        for (index, identity) in identities.enumerated() {
            guard let copy = part.copy() as? XMLElement else { throw DocumentError.invalidXML }
            set(copy, name: "id", value: identity.partID)
            parts.insertChild(copy, at: part.index + 1 + index)
            let members = Set(groups[index + 1])
            for nodeID in members {
                guard let node = nodeElements[nodeID] else { throw DocumentError.invalidNode }
                set(node, name: "partId", value: identity.partID)
                for edge in edgesByFrom[nodeID] ?? [] { set(edge, name: "partId", value: identity.partID) }
            }
            for (referenceIndex, reference) in references.enumerated() {
                let copy = try styleCopy(reference)
                guard let parent = anchors[referenceIndex].parent as? XMLElement
                else { throw DocumentError.invalidXML }
                set(copy, name: "id", value: identity.componentIDs[referenceIndex])
                set(copy, name: "linkData", value: identity.partID)
                parent.insertChild(copy, at: anchors[referenceIndex].index + 1)
                anchors[referenceIndex] = copy
            }
        }
        return true
    }

    private static func styleCopy(_ reference: XMLElement) throws -> XMLElement {
        let copy = XMLElement(name: reference.name ?? "component")
        for namespace in reference.namespaces ?? [] {
            guard let value = namespace.copy() as? XMLNode else { throw DocumentError.invalidXML }
            copy.addNamespace(value)
        }
        for attribute in reference.attributes ?? [] {
            guard let value = attribute.copy() as? XMLNode else { throw DocumentError.invalidXML }
            copy.addAttribute(value)
        }
        // Avoid copying descendant geometry just to discard it afterward.
        for child in reference.children ?? [] where !(child is XMLElement && child.name == "component") {
            guard let value = child.copy() as? XMLNode else { throw DocumentError.invalidXML }
            copy.addChild(value)
        }
        return copy
    }

    static func componentElements(_ model: XMLDocument) -> [XMLElement] {
        let roots = model.rootElement()?.elements(forName: "components").first?.elements(forName: "component") ?? []
        var pending = Array(roots.reversed())
        var result: [XMLElement] = []
        while let component = pending.popLast() {
            result.append(component)
            pending.append(contentsOf: component.elements(forName: "component").reversed())
        }
        return result
    }

    private static func referencesPart(_ component: XMLElement, id: String) -> Bool {
        component.attribute(forName: "linkDataType")?.stringValue == "partId"
            && component.attribute(forName: "linkData")?.stringValue == id
    }

    private static func set(_ element: XMLElement, name: String, value: String) {
        if let attribute = element.attribute(forName: name) {
            attribute.stringValue = value
        } else {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = name
            attribute.stringValue = value
            element.addAttribute(attribute)
        }
    }

    private static func connectedGroups(contents: DocumentContents, partIDs: Set<String>) throws -> [String: [[String]]]
    {
        let partByNode = Dictionary(
            uniqueKeysWithValues: contents.nodes.compactMap { node -> (String, String)? in
                node.partID.map { (node.id, $0) }
            })
        var nodesByPart: [String: [String]] = [:]
        var order: [String: Int] = [:]
        for (index, node) in contents.nodes.enumerated() {
            if let part = node.partID, partIDs.contains(part) {
                nodesByPart[part, default: []].append(node.id)
                order[node.id] = index
            }
        }
        var adjacency: [String: [String]] = [:]
        for edge in contents.edges {
            let from = partByNode[edge.fromID]
            let to = partByNode[edge.toID]
            if from.map(partIDs.contains) == true || to.map(partIDs.contains) == true {
                guard from == to else { throw DocumentError.invalidNode }
                adjacency[edge.fromID, default: []].append(edge.toID)
                adjacency[edge.toID, default: []].append(edge.fromID)
            }
        }
        var result: [String: [[String]]] = [:]
        for (part, nodes) in nodesByPart {
            var remaining = Set(nodes)
            var groups: [[String]] = []
            for node in nodes where remaining.remove(node) != nil {
                var group = [node]
                var cursor = 0
                while cursor < group.count {
                    for neighbor in adjacency[group[cursor]] ?? [] where remaining.remove(neighbor) != nil {
                        group.append(neighbor)
                    }
                    cursor += 1
                }
                group.sort { (order[$0] ?? 0) < (order[$1] ?? 0) }
                groups.append(group)
            }
            result[part] = groups.sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return (order[$0[0]] ?? 0) < (order[$1[0]] ?? 0)
            }
        }
        return result
    }
}
