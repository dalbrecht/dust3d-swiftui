import Dust3DDocument
import Foundation

/// Pure projection of supported linked-profile choices; it never repairs source metadata.
public enum PartProfileOptions {
    /// Search compatible exact part identities and titles, retaining source order and duplicate names.
    /// - Parameters:
    ///   - parts: Current document parts, including legacy identities that must stay preserved.
    ///   - ownerID: Inspected part, excluded to avoid a direct self dependency.
    ///   - query: Case-insensitive title or identity substring; empty includes all compatible choices.
    /// - Returns: Other parts with engine-compatible cut-face identities. Cycles are validated when applying the command.
    /// - Example: `PartProfileOptions.candidates(in: snapshot.parts, excluding: part.id, matching: "fin")`.
    public static func candidates(in parts: [DocumentPart], excluding ownerID: String, matching query: String)
        -> [DocumentPart]
    {
        let query = query.lowercased()
        return parts.filter {
            $0.canBeCutFaceProfile && $0.id != ownerID
                && (query.isEmpty || $0.title.lowercased().contains(query) || $0.id.lowercased().contains(query))
        }
    }

    /// Provide spoken profile names, using the source ID to distinguish duplicate visible titles.
    /// - Parameter candidates: The compatible, filtered parts currently shown in the chooser.
    /// - Returns: A spoken name keyed by each candidate's part ID.
    /// - Example: `PartProfileOptions.spokenTitles(for: visibleParts)`.
    public static func spokenTitles(for candidates: [DocumentPart]) -> [String: String] {
        let byTitle = Dictionary(grouping: candidates, by: \.title)
        var titles: [String: String] = [:]
        for candidate in candidates {
            let hasDuplicateTitle = (byTitle[candidate.title]?.count ?? 0) > 1
            titles[candidate.id] = hasDuplicateTitle ? "\(candidate.title), \(candidate.id)" : candidate.title
        }
        return titles
    }

    package static func candidates(in snapshot: EditorSnapshot, excluding ownerID: String, matching query: String)
        -> [DocumentPart]
    {
        let linkedIDs = Set(
            snapshot.parts.compactMap { part -> Data? in
                guard case .linkedPart(let id) = part.cutFace else { return nil }
                return Data(id.utf8)
            })
        let available = snapshot.parts.filter { $0.target == .cutFace || linkedIDs.contains(Data($0.id.utf8)) }
        let matches = candidates(in: available, excluding: ownerID, matching: query)
        guard matches.count > 1 else { return matches }
        let matchingIDs = Set(matches.map { Data($0.id.utf8) })

        var positions: [Data: (sum: Float, count: Int)] = [:]
        for node in snapshot.nodes {
            guard let id = node.partID.map({ Data($0.utf8) }), matchingIDs.contains(id) else { continue }
            positions[id, default: (0, 0)].sum += Float(node.value.position.x)
            positions[id, default: (0, 0)].count += 1
        }
        let centers = positions.mapValues { position -> Float in
            // Qt treats a fuzzy-zero sum as zero and puts empty profiles at the origin.
            abs(position.sum) <= 0.00001 ? 0 : position.sum / Float(position.count)
        }
        return matches.sorted { (centers[Data($0.id.utf8)] ?? 0) < (centers[Data($1.id.utf8)] ?? 0) }
    }
}
