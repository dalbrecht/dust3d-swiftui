import Dust3DDocument
import Foundation

extension EditorSnapshot {
    package var canSelectEditableGeometry: Bool { !editableGeometrySelection.nodes.isEmpty }

    /// Explicit owned graph that can be selected together without exposing protected edges to cascading Delete.
    var editableGeometrySelection: (nodes: Set<String>, edges: Set<String>) {
        let owners = Dictionary(
            uniqueKeysWithValues: nodes.compactMap { node in
                node.partID.map { (Data(node.id.utf8), Data($0.utf8)) }
            })
        var editableOwners = Set(parts.filter(\.isEditable).map { Data($0.id.utf8) })
        for edge in edges {
            let from = owners[Data(edge.fromID.utf8)]
            let to = owners[Data(edge.toID.utf8)]
            let owner = edge.partID.map { Data($0.utf8) }
            // Removing nodes also removes their incident edges. Exclude every implicated part
            // when a retained edge has missing or conflicting ownership.
            if owner == nil || from != owner || to != owner {
                editableOwners.subtract([from, to, owner].compactMap { $0 })
            }
        }
        editableOwners.formIntersection(owners.values)
        protectReferencedProfiles(owners: owners, editableOwners: &editableOwners)

        let selectedNodes = nodes.filter { node in
            node.isEditable && node.isVisible && owners[Data(node.id.utf8)].map(editableOwners.contains) == true
        }
        let selectedEdges = edges.filter { edge in
            edge.partID.map { editableOwners.contains(Data($0.utf8)) } == true
        }
        return (Set(selectedNodes.map(\.id)), Set(selectedEdges.map(\.id)))
    }

    private func protectReferencedProfiles(owners: [Data: Data], editableOwners: inout Set<Data>) {
        let partKeys = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, Data($0.id.utf8)) })
        var dependencies: [Data?: Set<Data>] = [:]
        func record(_ selection: CutFaceSelection?, owner: Data?) {
            // EmptyPartCleanup classifies UUID-shaped links and looks up the stored spelling.
            if case .linkedPart(let id) = selection, let target = partKeys[id] {
                dependencies[owner, default: []].insert(target)
            }
        }
        for part in parts { record(part.cutFace, owner: Data(part.id.utf8)) }
        for node in nodes { record(node.cutFace, owner: owners[Data(node.id.utf8)]) }
        var retained: [Data?] = partKeys.values.filter { !editableOwners.contains($0) }.map { $0 }
        retained.append(nil)
        while let owner = retained.popLast() {
            for dependency in dependencies[owner] ?? [] where editableOwners.remove(dependency) != nil {
                retained.append(dependency)
            }
        }
    }
}
