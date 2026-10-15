import Dust3DDocument
import Foundation

/// Failures decoding the versioned native clipboard transport.
public enum ClipboardError: Error, Equatable, Sendable {
    case invalidPayload
    case unsupportedVersion
}

/// Bounded binary transport: magic, four-byte JSON length, versioned selection metadata, then .ds3 bytes.
/// The caller supplies a new identifier on Copy/Cut; it is used only for transient paste placement.
public struct NodeClipboardPayload: Sendable {
    public let fragment: NodeClipboard
    public let identifier: String
    private static let magic = Data("Dust3D-Node-Clipboard\n".utf8)
    private static let metadataLimit = 2 * 1024 * 1024
    private static let archiveLimit = 256 * 1024 * 1024
    private struct Header: Codable {
        let version: Int
        let identifier: String
        let selectedIDs: [String]
    }

    /// Wrap an already validated fragment.
    /// - Parameters:
    ///   - fragment: Selected graph objects and embedded assets.
    ///   - identifier: Fresh Copy/Cut token, nonempty and at most 128 UTF-8 bytes.
    /// - Throws: `ClipboardError.invalidPayload` for an invalid token.
    public init(fragment: NodeClipboard, identifier: String) throws {
        guard !identifier.isEmpty, identifier.utf8.count <= 128 else { throw ClipboardError.invalidPayload }
        self.fragment = fragment
        self.identifier = identifier
    }

    /// Decode bounded metadata and validate its embedded archive and selection.
    /// - Parameter data: Native clipboard bytes; slices are rebased before indexing.
    /// - Throws: `ClipboardError` for malformed/unsupported transport, or `DocumentError` for invalid graph/archive data.
    public init(data: Data) throws {
        let bytes = Data(data)
        let prefix = Self.magic.count + 4
        guard bytes.count > prefix, bytes.count <= prefix + Self.metadataLimit + Self.archiveLimit,
            bytes.starts(with: Self.magic)
        else { throw ClipboardError.invalidPayload }
        let size = bytes[Self.magic.count..<prefix].reduce(0) { $0 * 256 + Int($1) }
        guard size > 0, size <= Self.metadataLimit, size <= bytes.count - prefix else {
            throw ClipboardError.invalidPayload
        }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: bytes[prefix..<(prefix + size)]) } catch {
            throw ClipboardError.invalidPayload
        }
        guard header.version == 1 else { throw ClipboardError.unsupportedVersion }
        guard !header.identifier.isEmpty, header.identifier.utf8.count <= 128,
            !header.selectedIDs.isEmpty, header.selectedIDs.count <= 10_000,
            header.selectedIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
            Set(header.selectedIDs).count == header.selectedIDs.count
        else {
            throw ClipboardError.invalidPayload
        }
        let document = try Dust3DDocument(data: Data(bytes[(prefix + size)...]))
        try self.init(
            fragment: NodeClipboard(document: document, selectedNodeIDs: Set(header.selectedIDs)),
            identifier: header.identifier)
    }

    /// Encode without base64 expansion; selection ordering and metadata keys are deterministic.
    /// - Returns: Native transport bytes, including the exact fragment archive.
    /// - Throws: `DocumentError.limitExceeded` when selection metadata exceeds 2 MiB.
    /// See the package README for a complete copy/paste example.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let header = try encoder.encode(
            Header(version: 1, identifier: identifier, selectedIDs: fragment.selectedNodeIDs.sorted()))
        guard header.count <= Self.metadataLimit else { throw DocumentError.limitExceeded }
        var result = Self.magic
        for shift in [24, 16, 8, 0] { result.append(UInt8((header.count >> shift) & 255)) }
        result.append(header)
        result.append(fragment.document.encoded())
        return result
    }
}
