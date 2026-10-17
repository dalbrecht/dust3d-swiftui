import Dust3DDocument

/// Recoverable native color conversion failure, independent of platform color types.
public enum ComponentColorDraftIssue: Equatable, Sendable {
    case unsupportedColorConversion

    /// Explain why an unconvertible native selection cannot be applied.
    public var message: String { "The chosen color cannot be converted to bounded sRGB channels." }
}

/// Immutable transient color editing state; changing a draft never writes a document.
public struct ComponentColorDraft: Equatable, Sendable {
    public let text: String
    public let conversionIssue: ComponentColorDraftIssue?
    /// Strictly interpreted hex, or nil while the draft is empty/invalid.
    public var parsedColor: DocumentColor? { DocumentColor(archiveValue: text) }
    /// Placeholder white is presentation-only and does not establish a source override.
    public var pickerColor: DocumentColor { parsedColor ?? DocumentColor(red: 255, green: 255, blue: 255) }
    /// Nonempty invalid text reaches the controller's explicit validation error on Apply.
    public var canApply: Bool { !text.isEmpty && conversionIssue == nil }

    /// Start/reset a draft from source metadata without repairing unsupported text.
    /// - Parameter source: Current component color state; absent/unsupported values start empty.
    public init(source: ComponentColorValue) {
        if case .value(let color) = source { text = color.archiveValue } else { text = "" }
        conversionIssue = nil
    }

    private init(text: String, issue: ComponentColorDraftIssue?) {
        self.text = text
        conversionIssue = issue
    }

    /// Replace transient text and clear a previous native conversion failure.
    /// - Parameter text: User-entered text; parsing and persistence occur separately.
    /// - Returns: A new draft with no document side effects.
    public func editing(_ text: String) -> Self { Self(text: text, issue: nil) }

    /// Accept a native selection only after the platform boundary converts it safely.
    /// - Parameter color: Converted byte channels, or nil for unsupported conversion.
    /// - Returns: A new draft, retaining existing text and a visible blocking cause on failure.
    public func choosing(_ color: DocumentColor?) -> Self {
        guard let color else { return Self(text: text, issue: .unsupportedColorConversion) }
        return Self(text: color.archiveValue, issue: nil)
    }

    /// Bound display work and text while retaining full unsupported source metadata elsewhere.
    /// - Parameter text: Original unsupported source value.
    /// - Returns: At most 80 characters from 320 UTF-8 bytes plus an ellipsis, or an empty marker.
    /// Truncated UTF-8 is repaired only for this display summary, never for document identity/data.
    public static func sourceSummary(_ text: String) -> String {
        let bytes = Array(text.utf8.prefix(321))
        guard !bytes.isEmpty else { return "(empty)" }
        let bounded = String(decoding: bytes.prefix(320), as: UTF8.self)
        let characters = bounded.prefix(81)
        let isTruncated = bytes.count > 320 || characters.count > 80
        return String(characters.prefix(80)) + (isTruncated ? "…" : "")
    }
}
