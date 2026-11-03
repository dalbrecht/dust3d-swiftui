import Foundation

/// Validated source identity embedded in an executable at link time, independent of mutable bundle files.
public struct BuildIdentityMetadata: Equatable, Sendable {
    public let sourceRevision: String
    public let coreRevision: String
    public let sourceDigest: String
    public let isDirty: Bool
    public let coreDigest: String?
    public let coreIsDirty: Bool?
    public var summary: String { isDirty ? "Modified source tree" : "Clean source tree" }

    /// Decode bounded linker metadata. Missing or invalid identities must remain explicitly unavailable.
    /// - Parameter data: UTF-8 JSON from the executable's build-identity section.
    /// - Throws: `BuildIdentityError` preserving decoding causes and invalid field names.
    public init(data: Data) throws {
        guard data.count <= 4096 else { throw BuildIdentityError.oversized(data.count) }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) } catch {
            throw BuildIdentityError.decoding(cause: error)
        }
        guard payload.schemaVersion == 1 else { throw BuildIdentityError.unsupportedVersion(payload.schemaVersion) }
        for (name, value, lengths) in [
            ("sourceRevision", payload.sourceRevision, [40, 64]),
            ("coreRevision", payload.coreRevision, [40, 64]),
            ("sourceDigest", payload.sourceDigest, [64]),
        ] {
            guard lengths.contains(value.utf8.count),
                value.utf8.allSatisfy({
                    (48...57).contains($0) || (97...102).contains($0)
                })
            else { throw BuildIdentityError.invalidField(name) }
        }
        guard (payload.coreDigest == nil) == (payload.coreIsDirty == nil) else {
            throw BuildIdentityError.invalidField("localCoreIdentity")
        }
        if let digest = payload.coreDigest {
            guard digest.utf8.count == 64,
                digest.utf8.allSatisfy({
                    (48...57).contains($0) || (97...102).contains($0)
                })
            else { throw BuildIdentityError.invalidField("coreDigest") }
        }
        coreDigest = payload.coreDigest
        coreIsDirty = payload.coreIsDirty
        sourceRevision = payload.sourceRevision
        coreRevision = payload.coreRevision
        sourceDigest = payload.sourceDigest
        isDirty = payload.isDirty
    }

    private struct Payload: Decodable {
        let schemaVersion: Int
        let sourceRevision: String
        let coreRevision: String
        let sourceDigest: String
        let isDirty: Bool
        let coreDigest: String?
        let coreIsDirty: Bool?
    }
}

/// Explicit diagnostic failures; unavailable metadata never becomes an invented source revision.
public enum BuildIdentityError: Error, LocalizedError, Sendable {
    case missing
    case oversized(Int)
    case decoding(cause: any Error)
    case unsupportedVersion(Int)
    case invalidField(String)

    public var errorDescription: String? {
        switch self {
        case .missing: "This executable has no embedded build identity."
        case .oversized(let count): "Build identity exceeds its 4096-byte limit (\(count) bytes)."
        case .decoding(let cause): "Build identity could not be decoded: \(cause.localizedDescription)"
        case .unsupportedVersion(let version): "Build identity schema \(version) is unsupported."
        case .invalidField(let name): "Build identity contains an invalid \(name)."
        }
    }
}
