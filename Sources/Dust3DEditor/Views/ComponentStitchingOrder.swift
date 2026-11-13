import Dust3DDocument
import Dust3DEditorModel
import Foundation

/// Stitching line loft order follows the authored sequence of direct siblings.
struct ComponentStitchingOrder {
    struct Ordinal: Equatable {
        let position: Int
        let count: Int
    }

    let hasUngroupedStitching: Bool
    private let lineCounts: [Data?: Int]
    private let ordinals: [Data: Ordinal]

    init(snapshot: EditorSnapshot) {
        let roles = Dictionary(
            snapshot.parts.compactMap { part in part.target.map { (Data(part.id.utf8), $0) } },
            uniquingKeysWith: { first, _ in first })
        var lines: [Data?: [Data]] = [:]
        var hasRootStitching = false
        for row in snapshot.componentTree.rows {
            guard let partID = row.component.partID, let role = roles[Data(partID.utf8)],
                role == .stitchingLine || role == .stitchingLoop
            else { continue }
            let parent = row.component.parentID.map { Data($0.utf8) }
            if parent == nil { hasRootStitching = true }
            if role == .stitchingLine { lines[parent, default: []].append(Data(row.id.utf8)) }
        }
        var positions: [Data: Ordinal] = [:]
        for siblings in lines.values where siblings.count > 1 {
            for (index, key) in siblings.enumerated() {
                positions[key] = Ordinal(position: index + 1, count: siblings.count)
            }
        }
        hasUngroupedStitching = hasRootStitching
        lineCounts = lines.mapValues(\.count)
        ordinals = positions
    }

    func ordinal(for componentID: String) -> Ordinal? { ordinals[Data(componentID.utf8)] }

    func hasLineOrder(in parentID: String?) -> Bool {
        (lineCounts[parentID.map { Data($0.utf8) }] ?? 0) > 1
    }
}
