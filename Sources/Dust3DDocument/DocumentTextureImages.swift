import Foundation

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
public enum TextureImageReferenceError: LocalizedError, Equatable, Sendable {
    case invalidImageIdentity(String)
    case missingAsset(String)
    case ambiguousAsset(String)
    case invalidAssetKind(String)

    /// Preserve the original resource identity/key in a user-facing diagnostic.
    public var errorDescription: String? {
        switch self {
        case .invalidImageIdentity(let id): return "The image identity is invalid: \(id)."
        case .missingAsset(let name): return "The document has no image asset \(name)."
        case .ambiguousAsset(let id): return "Multiple retained assets match image \(id)."
        case .invalidAssetKind(let name): return "The referenced resource is not an image asset: \(name)."
        }
    }
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
        let byIdentity = index(assets)
        var seen: Set<[UInt8]> = []
        var result: [DocumentTextureImageReference] = []
        for imageID in imageIDs where !imageID.isEmpty {
            guard let identity = identityBytes(imageID) else {
                throw TextureImageReferenceError.invalidImageIdentity(imageID)
            }
            guard seen.insert(identity).inserted else { continue }
            result.append(try resolve(identity, in: byIdentity))
        }
        return result
    }

    static func reference(imageID: String, assets: [DocumentTextureAssetMetadata]) throws
        -> DocumentTextureImageReference
    {
        guard let identity = identityBytes(imageID) else {
            throw TextureImageReferenceError.invalidImageIdentity(imageID)
        }
        return try resolve(identity, in: index(assets))
    }

    private static func index(_ assets: [DocumentTextureAssetMetadata]) -> [[UInt8]: [DocumentTextureAssetMetadata]] {
        var byIdentity: [[UInt8]: [DocumentTextureAssetMetadata]] = [:]
        for asset in assets where asset.name.hasPrefix("images/") {
            // Match the reference reader's first path segment and filename stem.
            // These are archive keys only: no path is extracted to the filesystem.
            guard let identity = identityBytes(stem(asset.name)) else { continue }
            byIdentity[identity, default: []].append(asset)
        }
        return byIdentity
    }

    private static func resolve(_ identity: [UInt8], in byIdentity: [[UInt8]: [DocumentTextureAssetMetadata]])
        throws(TextureImageReferenceError)
        -> DocumentTextureImageReference
    {
        let canonical = "{" + String(decoding: identity, as: UTF8.self) + "}"
        let candidates = byIdentity[identity] ?? []
        let images = candidates.filter { $0.kind == "asset" }
        guard images.count <= 1 else { throw TextureImageReferenceError.ambiguousAsset(canonical) }
        guard let asset = images.first else {
            if let candidate = candidates.first { throw TextureImageReferenceError.invalidAssetKind(candidate.name) }
            throw TextureImageReferenceError.missingAsset("images/\(canonical).png")
        }
        return DocumentTextureImageReference(
            imageID: canonical, assetName: asset.name, encodedByteCount: asset.byteCount)
    }

    private static func stem(_ name: String) -> String {
        let tail = name.dropFirst("images/".count)
        let filename = tail.split(separator: "/", omittingEmptySubsequences: false).first ?? ""
        return String(filename.split(separator: ".", omittingEmptySubsequences: false).first ?? "")
    }

    static func inventory(assets: [DocumentTextureAssetMetadata]) -> [DocumentColorImageAsset] {
        let indexed = index(assets)
        var seen: Set<[UInt8]> = []
        var result: [DocumentColorImageAsset] = []
        for asset in assets where asset.name.hasPrefix("images/") {
            let source = stem(asset.name)
            guard let identity = identityBytes(source) else {
                result.append(
                    DocumentColorImageAsset(
                        id: [0] + Array(asset.name.utf8), imageID: nil,
                        assetName: asset.name, encodedByteCount: asset.byteCount, issue: .invalidImageIdentity(source)))
                continue
            }
            guard seen.insert(identity).inserted else { continue }
            let canonical = "{" + String(decoding: identity, as: UTF8.self) + "}"
            do {
                let reference = try resolve(identity, in: indexed)
                result.append(
                    DocumentColorImageAsset(
                        id: Array(canonical.utf8), imageID: canonical,
                        assetName: reference.assetName, encodedByteCount: reference.encodedByteCount, issue: nil))
            } catch {
                result.append(
                    DocumentColorImageAsset(
                        id: Array(canonical.utf8), imageID: canonical,
                        assetName: asset.name, encodedByteCount: asset.byteCount, issue: error))
            }
        }
        return result
    }

    static func identityBytes(_ text: String) -> [UInt8]? {
        guard text.utf8.count == 36 || text.utf8.count == 38 else { return nil }
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
