import Dust3DDocument
import Dust3DEditorModel
import Foundation

struct CanvasNodeSidebarRow: Identifiable {
    let id: String
    let title: String
    let partTitle: String?
    let status: String?
    let ordinal: Int

    var accessibilityLabel: String {
        [title, partTitle, status, "Node \(ordinal)"].compactMap { $0 }.joined(separator: ", ")
    }

    static func rows(in snapshot: EditorSnapshot) -> [Self] {
        let parts = snapshot.parts.reduce(into: [Data: DocumentPart]()) { parts, part in
            let key = Data(part.id.utf8)
            if parts[key] == nil { parts[key] = part }
        }
        return snapshot.nodes.enumerated().map { index, node in
            let part = node.partID.flatMap { parts[Data($0.utf8)] }
            let status: String?
            if part?.isDisabled == true {
                status = "Disabled in mesh"
            } else if !node.isVisible {
                status = "Hidden in canvas"
            } else if !node.isEditable {
                status = "Locked"
            } else {
                status = nil
            }
            return Self(id: node.id, title: node.title, partTitle: part?.title, status: status, ordinal: index + 1)
        }
    }

    static func filter(_ rows: [Self], matching query: String) -> [Self] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return rows }
        return rows.filter { row in
            let searchable = "\(row.title) \(row.partTitle ?? "") \(row.status ?? "") \(row.id)"
            return terms.allSatisfy { searchable.localizedStandardContains(String($0)) }
        }
    }
}

struct CanvasNodeSidebarPresentation {
    let profileLease: UUID?
    let target: EditorStore.CanvasNodeSelectionTarget
    let selectionRevision: Int
    let selectedIDs: Set<String>
    private let allRows: [CanvasNodeSidebarRow]

    init(snapshot: EditorSnapshot, profileLease: UUID?, target: EditorStore.CanvasNodeSelectionTarget) {
        self.profileLease = profileLease
        self.target = target
        selectionRevision = snapshot.selectionRevision
        selectedIDs = snapshot.selectedIDs
        allRows = CanvasNodeSidebarRow.rows(in: snapshot)
    }

    func rows(matching query: String) -> [CanvasNodeSidebarRow] {
        CanvasNodeSidebarRow.filter(allRows, matching: query)
    }
}
