/// Exact UTF-8 lookup identity shared by stored names and native editing drafts.
/// Swift canonical String equality can merge spellings that the inherited C++ lookup distinguishes.
public struct BoneNameIdentity: Equatable, Sendable {
    /// Retained spelling for storage or editing, including legacy values.
    public let rawValue: String

    /// Retain a spelling for byte-sensitive comparison; document commands validate applied edits.
    /// - Parameter rawValue: Original stored or draft name, including case and spacing.
    /// - Example: `BoneNameIdentity("Root")`.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Compare the UTF-8 bytes used by the inherited lookup.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.utf8.elementsEqual(rhs.rawValue.utf8)
    }
}
