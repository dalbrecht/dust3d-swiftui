import Dust3DDocument

/// Bounded, framework-independent inspector text derived from retained source metadata.
public struct ComponentColorImagePresentation: Equatable, Sendable {
    public let source: String
    public let resource: String?

    /// Describe an override without asserting that metadata-eligible bytes have decoded successfully.
    /// - Parameters: value is the exact source interpretation; assets is the document's metadata inventory.
    public init(value: ComponentColorImageValue, assets: [DocumentColorImageAsset]) {
        switch value {
        case .unset:
            source = "No explicit image override."
            resource = nil
        case .unsupported(let raw):
            source = "Unsupported image reference: \(Self.summary(raw))"
            resource = "Import or choose an image to replace it, or clear the override."
        case .reference(let raw):
            source = "Image: \(Self.summary(raw))"
            let canonical = raw.utf8.count == 36 ? Array(("{" + raw + "}").utf8) : Array(raw.utf8)
            if let asset = assets.first(where: { $0.id == canonical }) {
                resource =
                    asset.issue.map { Self.summary($0.localizedDescription) }
                    ?? "Retained resource: \(Self.summary(asset.assetName))"
            } else {
                resource = "The referenced image is missing from this document."
            }
        }
    }

    /// Bound both UTF-8 work and visible characters, including unusually long combining sequences.
    /// - Parameter text: Untrusted retained source text; never modified in the document.
    /// - Returns: At most 80 characters plus an ellipsis; empty input has an explicit label.
    public static func summary(_ text: String) -> String {
        let bytes = Array(text.utf8.prefix(321))
        guard !bytes.isEmpty else { return "(empty)" }
        let characters = String(decoding: bytes.prefix(320), as: UTF8.self).prefix(81)
        return String(characters.prefix(80)) + (bytes.count > 320 || characters.count > 80 ? "…" : "")
    }
}
