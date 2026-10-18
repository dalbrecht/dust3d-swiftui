/// A retained color-image reference. Bytes are not decoded or modified by this query.
public struct DocumentTextureImageReference: Equatable, Sendable {
    public let imageID: String
    public let assetName: String
    public let encodedByteCount: Int

    /// Compare opaque image identities and archive keys without Unicode normalization.
    /// - Parameters: lhs and rhs are retained reference metadata.
    /// - Returns: True only for identical UTF-8 keys and encoded byte counts.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.imageID.utf8.elementsEqual(rhs.imageID.utf8)
            && lhs.assetName.utf8.elementsEqual(rhs.assetName.utf8)
            && lhs.encodedByteCount == rhs.encodedByteCount
    }
}

/// Explicit failures resolving a referenced image; unrelated opaque assets remain preserved.
public enum TextureImageReferenceError: Error, Equatable, Sendable {
    case invalidImageIdentity(String)
    case missingAsset(String)
    case ambiguousAsset(String)
    case invalidAssetKind(String)
}

struct DocumentTextureAssetMetadata {
    let name: String
    let kind: String
    let byteCount: Int
}

enum DocumentTextureImages {
    static func references(imageIDs: [String], assets: [DocumentTextureAssetMetadata]) throws
        -> [DocumentTextureImageReference]
    {
        var byIdentity: [[UInt8]: [DocumentTextureAssetMetadata]] = [:]
        for asset in assets where asset.name.hasPrefix("images/") {
            // Match the reference reader's first path segment and filename stem.
            // These are archive keys only: no path is extracted to the filesystem.
            let tail = asset.name.dropFirst("images/".count)
            let filename = tail.split(separator: "/", omittingEmptySubsequences: false).first ?? ""
            let stem = filename.split(separator: ".", omittingEmptySubsequences: false).first ?? ""
            guard let identity = identityBytes(String(stem)) else { continue }
            byIdentity[identity, default: []].append(asset)
        }
        var seen: Set<[UInt8]> = []
        var result: [DocumentTextureImageReference] = []
        for imageID in imageIDs where !imageID.isEmpty {
            guard let identity = identityBytes(imageID) else {
                throw TextureImageReferenceError.invalidImageIdentity(imageID)
            }
            guard seen.insert(identity).inserted else { continue }
            let canonical = "{" + String(decoding: identity, as: UTF8.self) + "}"
            let candidates = byIdentity[identity] ?? []
            let images = candidates.filter { $0.kind == "asset" }
            guard images.count <= 1 else { throw TextureImageReferenceError.ambiguousAsset(canonical) }
            guard let asset = images.first else {
                if let candidate = candidates.first {
                    throw TextureImageReferenceError.invalidAssetKind(candidate.name)
                }
                throw TextureImageReferenceError.missingAsset("images/\(canonical).png")
            }
            result.append(
                DocumentTextureImageReference(
                    imageID: canonical, assetName: asset.name, encodedByteCount: asset.byteCount))
        }
        return result
    }

    private static func identityBytes(_ text: String) -> [UInt8]? {
        var bytes = Array(text.utf8)
        if bytes.count == 38, bytes.first == 123, bytes.last == 125 {
            bytes = Array(bytes.dropFirst().dropLast())
        }
        // The engine's identity rule accepts opaque non-hex characters and keeps case.
        // All-zero identities are valid there; null means an empty identity only.
        guard bytes.count == 36, !bytes.contains(0), [8, 13, 18, 23].allSatisfy({ bytes[$0] == 45 }) else { return nil }
        return bytes
    }
}
