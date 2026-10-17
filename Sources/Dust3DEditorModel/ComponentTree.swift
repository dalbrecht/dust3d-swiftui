import Dust3DDocument
import Foundation

/// A pure presentation row; identity and links remain owned by the document component.
public struct ComponentTreeRow: Identifiable, Equatable, Sendable {
    public let component: DocumentComponent
    public let depth: Int
    public let title: String
    public var id: String { component.id }
    public var hasChildren: Bool { !component.childIDs.isEmpty }
}

/// Cached hierarchy presentation. Unsupported hierarchy data stays preservable and its cause stays visible.
public struct ComponentTree: Sendable {
    public let rows: [ComponentTreeRow]
    public let failureDescription: String?

    /// Interpret the bounded hierarchy off the UI actor; failure does not prevent unrelated graph editing.
    /// - Parameter document: The immutable archive whose component names and ordering should be displayed.
    public init(document: Dust3DDocument) {
        do {
            let components = try document.components()
            var depths: [String: Int] = [:]
            rows = components.enumerated().map { index, component in
                let depth = component.parentID.flatMap { depths[$0] }.map { $0 + 1 } ?? 0
                depths[component.id] = depth
                let name = component.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = component.childIDs.isEmpty ? "Component" : "Group"
                return ComponentTreeRow(
                    component: component, depth: depth, title: name.isEmpty ? "\(fallback) \(index + 1)" : name)
            }
            failureDescription = nil
        } catch {
            rows = []
            failureDescription = String(describing: error)
        }
    }

    /// Available non-no-op sibling moves in upstream menu order.
    /// - Parameter id: Existing component identity; unknown identities return no moves.
    /// - Returns: Moves that change its final sibling index, independent of transient collapse state.
    public func orderMoves(for id: String) -> [ComponentOrderMove] {
        guard let row = rows.first(where: { $0.id == id }) else { return [] }
        let siblings = rows.filter { $0.component.parentID == row.component.parentID }
        let index = siblings.prefix { $0.id != id }.count
        return ComponentOrderMove.allCases.filter { $0.destinationIndex(from: index, count: siblings.count) != nil }
    }

    /// Eligible non-no-op parent destinations, excluding the complete source subtree and unsupported links.
    /// - Parameters:
    ///   - id: Source component identity; missing identities produce no choices.
    ///   - query: Optional case-insensitive title/identity filter; surrounding whitespace is ignored.
    /// - Returns: Root first when applicable, followed by supported groups in document order.
    public func parentOptions(for id: String, matching query: String = "") -> [ComponentParentOption] {
        guard let source = rows.first(where: { $0.id == id }) else { return [] }
        var options: [ComponentParentOption] = []
        if source.component.parentID != nil { options.append(.init(id: .root, title: "Document Root")) }
        var isWithinSource = false
        for row in rows {
            if row.id == id {
                isWithinSource = true
                continue
            }
            if isWithinSource {
                if row.depth > source.depth { continue }
                isWithinSource = false
            }
            if row.component.isGroup, row.id != source.component.parentID {
                options.append(.init(id: .component(row.id), title: row.title))
            }
        }
        let filter = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return options }
        return options.filter {
            $0.title.range(of: filter, options: .caseInsensitive) != nil
                || $0.id.componentID?.range(of: filter, options: .caseInsensitive) != nil
        }
    }

    /// Filter descendants of collapsed groups in linear time; collapse state is local to its window.
    /// - Parameter identities: Component IDs whose own row remains visible while descendants are hidden.
    /// - Returns: Visible rows in unchanged XML preorder. Unknown IDs and leaf IDs have no effect.
    public func visibleRows(collapsing identities: Set<String>) -> [ComponentTreeRow] {
        var hiddenBelow: Int?
        return rows.filter { row in
            if let depth = hiddenBelow {
                if row.depth > depth { return false }
                hiddenBelow = nil
            }
            if row.hasChildren && identities.contains(row.id) { hiddenBelow = row.depth }
            return true
        }
    }
}
