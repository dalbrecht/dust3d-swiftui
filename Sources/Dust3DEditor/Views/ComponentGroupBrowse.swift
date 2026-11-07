import Dust3DEditorModel
import Foundation

/// One group's direct child rows and breadcrumb in source order.
struct ComponentGroupBrowse {
    let path: [ComponentTreeRow]
    let children: [ComponentTreeRow]
    private let childKeys: Set<Data>

    init?(tree: ComponentTree, groupID: String) {
        guard tree.failureDescription == nil else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: tree.rows.map { (Data($0.id.utf8), $0) })
        guard let group = byID[Data(groupID.utf8)], group.component.isGroup else { return nil }
        children = group.component.childIDs.compactMap { byID[Data($0.utf8)] }
        childKeys = Set(children.map { Data($0.id.utf8) })
        var ancestors = [group]
        var parent = group.component.parentID
        while let id = parent, let row = byID[Data(id.utf8)] {
            ancestors.append(row)
            parent = row.component.parentID
        }
        path = Array(ancestors.reversed())
    }

    func contains(_ id: String) -> Bool { childKeys.contains(Data(id.utf8)) }
}
