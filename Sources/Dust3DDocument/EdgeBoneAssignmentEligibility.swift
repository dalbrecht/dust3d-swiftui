import Foundation

/// Pure metadata admission shared by captured controls and atomic archive commands.
public enum EdgeBoneAssignmentEligibility {
    /// Resolve exact editable edge identities without XML parsing or native evaluation.
    /// - Parameters:
    ///   - nodes: Decoded nodes and effective endpoint editability.
    ///   - edges: Explicit stored edges, without inferring adjacency.
    ///   - parts: Decoded owners used to reject byte-distinct aliases and read-only assignments.
    /// - Returns: UTF-8 edge identity keys. Legacy absent owners retain single-edge binding behavior.
    /// - Example: `let eligible = EdgeBoneAssignmentEligibility.edgeIDs(nodes: nodes, edges: edges, parts: parts)`.
    public static func edgeIDs(nodes: [DocumentNode], edges: [DocumentEdge], parts: [DocumentPart]) -> Set<Data> {
        let partIDs = Set(parts.map { Data($0.id.utf8) })
        let editableParts = Set(parts.filter(\.isEditable).map { Data($0.id.utf8) })
        let editableNodes = Set(
            nodes.filter {
                $0.isEditable && ($0.partID.map { partIDs.contains(Data($0.utf8)) } ?? true)
            }.map { Data($0.id.utf8) })
        return Set(
            edges.filter {
                editableNodes.contains(Data($0.fromID.utf8)) && editableNodes.contains(Data($0.toID.utf8))
                    && ($0.partID.map { editableParts.contains(Data($0.utf8)) } ?? true)
            }.map { Data($0.id.utf8) })
    }
}
