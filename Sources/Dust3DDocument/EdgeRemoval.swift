import Foundation

/// Validate the entire captured edge set before one traversal of the private XML tree.
enum EdgeRemoval {
    static func apply(_ ids: [String], model: XMLDocument, contents: DocumentContents) throws -> Bool {
        guard ids.count <= 20_000 else { throw DocumentError.limitExceeded }
        if ids.isEmpty { return false }
        let selected = Set(ids)
        let edges = Dictionary(uniqueKeysWithValues: contents.edges.map { ($0.id, $0) })
        let editable = Set(contents.nodes.filter(\.isEditable).map(\.id))
        guard selected.count == ids.count,
            ids.allSatisfy({ id in
                guard let edge = edges[id] else { return false }
                return editable.contains(edge.fromID) && editable.contains(edge.toID)
            })
        else { throw DocumentError.invalidNode }
        let elements = model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge") ?? []
        for edge in elements where selected.contains(edge.attribute(forName: "id")?.stringValue ?? "") {
            edge.detach()
        }
        return true
    }
}
