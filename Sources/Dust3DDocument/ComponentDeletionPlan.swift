import Foundation

/// Explicit subtree deletion preserves graph parts until their final known component reference is removed.
public struct ComponentDeletionPlan: Sendable {
    /// Outermost selected components in source preorder; descendants are removed by their parent XML.
    public let rootComponentIDs: [String]
    public let removedComponentIDs: Set<String>
    public let removedPartIDs: Set<String>
    public let removedNodeIDs: Set<String>
    public let removedEdgeIDs: Set<String>

    /// Preflight a complete immutable hierarchy/graph without interpreting opaque links or soft references.
    /// - Parameters: components, nodes, edges and parts are the source snapshot; selectedIDs are explicit row targets.
    /// - Throws: Missing selected component, duplicate source identities, invalid hierarchy or existing count limits.
    /// - Example: `try ComponentDeletionPlan(components: rows, nodes: nodes, edges: edges, parts: parts, selectedIDs: [id])`.
    public init(
        components: [DocumentComponent], nodes: [DocumentNode], edges: [DocumentEdge], parts: [DocumentPart],
        selectedIDs: [String]
    ) throws {
        guard components.count <= 10_000, nodes.count <= 10_000, parts.count <= 10_000,
            edges.count <= 20_000, selectedIDs.count <= 10_000
        else { throw DocumentError.limitExceeded }
        for ids in [components.map(\.id), nodes.map(\.id), edges.map(\.id), parts.map(\.id)] {
            guard Set(ids).count == ids.count else { throw DocumentError.invalidComponentStructure }
        }
        let indexed = Dictionary(uniqueKeysWithValues: components.map { (Data($0.id.utf8), $0) })
        for id in selectedIDs.sorted() where indexed[Data(id.utf8)] == nil {
            throw DocumentError.missingComponent(id)
        }
        var removed = Set<Data>()
        var pending = selectedIDs.map { Data($0.utf8) }
        while let key = pending.popLast() {
            guard removed.insert(key).inserted else { continue }
            guard let row = indexed[key] else { throw DocumentError.invalidComponentStructure }
            pending.append(contentsOf: row.childIDs.map { Data($0.utf8) })
        }
        rootComponentIDs = components.filter {
            removed.contains(Data($0.id.utf8)) && $0.parentID.map { removed.contains(Data($0.utf8)) } != true
        }.map(\.id)
        removedComponentIDs = Set(components.filter { removed.contains(Data($0.id.utf8)) }.map(\.id))
        let candidates = Set(
            components.filter { removed.contains(Data($0.id.utf8)) }.compactMap(\.partID).map { Data($0.utf8) })
        let survivingReferences = Set(
            components.filter { !removed.contains(Data($0.id.utf8)) }.compactMap(\.partID).map { Data($0.utf8) })
        removedPartIDs = Set(
            parts.filter {
                let key = Data($0.id.utf8)
                return candidates.contains(key) && !survivingReferences.contains(key)
            }.map(\.id))
        let partKeys = Set(removedPartIDs.map { Data($0.utf8) })
        removedNodeIDs = Set(nodes.filter { $0.partID.map { partKeys.contains(Data($0.utf8)) } == true }.map(\.id))
        let nodeKeys = Set(removedNodeIDs.map { Data($0.utf8) })
        removedEdgeIDs = Set(
            edges.filter {
                $0.partID.map { partKeys.contains(Data($0.utf8)) } == true
                    || nodeKeys.contains(Data($0.fromID.utf8)) || nodeKeys.contains(Data($0.toID.utf8))
            }.map(\.id))
    }
}

enum ComponentSubtreeDeletion {
    static func apply(_ model: XMLDocument, contents: DocumentContents, ids: [String]) throws -> Bool {
        guard ids.count <= 10_000 else { throw DocumentError.limitExceeded }
        guard !ids.isEmpty else { return false }
        let plan = try ComponentDeletionPlan(
            components: ComponentHierarchy.read(model), nodes: contents.nodes, edges: contents.edges,
            parts: contents.parts, selectedIDs: ids)
        let roots = Set(plan.rootComponentIDs.map { Data($0.utf8) })
        let elements = PartSplitting.componentElements(model)
        try Task.checkCancellation()
        for element in elements where roots.contains(Data((element.attribute(forName: "id")?.stringValue ?? "").utf8)) {
            element.detach()
        }
        for (container, child, ids) in [
            ("parts", "part", plan.removedPartIDs), ("nodes", "node", plan.removedNodeIDs),
            ("edges", "edge", plan.removedEdgeIDs),
        ] {
            let keys = Set(ids.map { Data($0.utf8) })
            let parent = DocumentXML.childElements(model.rootElement(), named: container).first
            for element in DocumentXML.childElements(parent, named: child)
            where keys.contains(Data((element.attribute(forName: "id")?.stringValue ?? "").utf8)) {
                element.detach()
            }
        }
        return true
    }
}
