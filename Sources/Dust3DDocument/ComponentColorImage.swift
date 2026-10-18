/// Preserve missing, exact valid source identities and unsupported color-image metadata independently.
public enum ComponentColorImageValue: Equatable, Sendable {
    case unset
    case reference(String)
    case unsupported(String)

    /// Compare opaque source text by UTF-8 bytes without Unicode normalization.
    /// - Parameters: lhs and rhs are source interpretations, not resolved asset payloads.
    /// - Returns: True for the same case and byte-identical associated text.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.unset, .unset): return true
        case (.reference(let first), .reference(let second)), (.unsupported(let first), .unsupported(let second)):
            return first.utf8.elementsEqual(second.utf8)
        default: return false
        }
    }
}
