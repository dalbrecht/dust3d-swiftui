/// One retained image resource group. Metadata eligibility does not imply decoded pixel validity.
public struct DocumentColorImageAsset: Identifiable, Equatable, Sendable {
    /// Exact byte identity for stable UI rows, including Unicode-distinct opaque source identities.
    public let id: [UInt8]
    public let imageID: String?
    public let assetName: String
    public let encodedByteCount: Int
    public let issue: TextureImageReferenceError?
    /// Whether resource metadata permits a subsequent platform-validation/assignment attempt.
    public var canAssign: Bool { imageID != nil && issue == nil }

    /// Compare retained names and identities without Unicode normalization.
    /// - Parameters: lhs and rhs are immutable resource metadata.
    /// - Returns: True only for matching byte identities, resource keys, size and issue.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.imageID.map { Array($0.utf8) } == rhs.imageID.map { Array($0.utf8) }
            && lhs.assetName.utf8.elementsEqual(rhs.assetName.utf8)
            && lhs.encodedByteCount == rhs.encodedByteCount && lhs.issue == rhs.issue
    }
}
