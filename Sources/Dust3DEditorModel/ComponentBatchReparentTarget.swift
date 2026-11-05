import Dust3DDocument
import Foundation

/// The selected component IDs and editing epochs at the time the parent chooser opens.
public struct ComponentBatchReparentTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    let ids: [String]
    private let options: [ComponentParentOption]

    public init?(snapshot: EditorSnapshot) {
        guard !snapshot.selectedComponentIDs.isEmpty else { return nil }
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        ids = Array(snapshot.selectedComponentIDs)
        options = Self.destinations(rows: snapshot.componentTree.rows, ids: ids)
    }

    /// Destinations that can move at least one selected subtree. Root precedes source-ordered groups.
    public func parentOptions(matching query: String = "") -> [ComponentParentOption] {
        let filter = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return options }
        return options.filter {
            $0.title.range(of: filter, options: .caseInsensitive) != nil
                || $0.id.componentID?.range(of: filter, options: .caseInsensitive) != nil
        }
    }

    private static func destinations(rows: [ComponentTreeRow], ids: [String]) -> [ComponentParentOption] {
        let selected = Set(ids.map { Data($0.utf8) })
        var subtreeDepth: Int?
        var groups: [ComponentParentOption] = []
        var rootCount = 0
        var parentCounts: [Data: Int] = [:]
        for row in rows {
            if let depth = subtreeDepth, row.depth > depth { continue }
            subtreeDepth = nil
            if selected.contains(Data(row.id.utf8)) {
                subtreeDepth = row.depth
                rootCount += 1
                if let parent = row.component.parentID { parentCounts[Data(parent.utf8), default: 0] += 1 }
            } else if row.component.isGroup {
                groups.append(.init(id: .component(row.id), title: row.title))
            }
        }
        guard rootCount > 0 else { return [] }
        let available = groups.filter { option in
            guard let id = option.id.componentID else { return false }
            return parentCounts[Data(id.utf8)] != rootCount
        }
        let nestedCount = parentCounts.values.reduce(0, +)
        return nestedCount > 0 ? [.init(id: .root, title: "Document Root")] + available : available
    }

    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        context.isCurrent(in: snapshot)
    }
}

extension EditorState {
    /// Move the captured selection in one history operation.
    public mutating func reparentComponents(to parent: ComponentParent, target: ComponentBatchReparentTarget) throws {
        try Task.checkCancellation()
        guard target.isCurrent(in: snapshot) else { throw EditorError.staleComponentMove }
        var next = self
        try next.apply([.reparentComponents(ids: target.ids, parentID: parent.componentID)])
        try Task.checkCancellation()
        self = next
    }
}
