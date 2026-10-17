import Dust3DDocument

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
}
