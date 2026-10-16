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
