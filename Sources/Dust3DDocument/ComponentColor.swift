/// Eight-bit source color channels. Archive alpha precedes RGB; opaque values omit alpha.
/// Color-space conversion belongs at the UI/rendering boundary, not in this value.
public struct DocumentColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    /// Construct bounded channels without allowing an invalid numeric state.
    /// - Parameters:
    ///   - red: Red channel from 0 through 255.
    ///   - green: Green channel from 0 through 255.
    ///   - blue: Blue channel from 0 through 255.
    ///   - alpha: Opacity channel, defaulting to 255 (opaque).
    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parse exact ASCII `#RRGGBB` or `#AARRGGBB` archive notation.
    /// - Parameter archiveValue: Original source text; whitespace/names/shorthand are unsupported.
    /// - Returns: A bounded color, or nil without repairing unsupported source text.
    /// - Example: `DocumentColor(archiveValue: "#80102030")` has alpha 128 and red 16.
    public init?(archiveValue: String) {
        let bytes = archiveValue.utf8
        guard bytes.count == 7 || bytes.count == 9, bytes.first == 35,
            bytes.dropFirst().allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
            ),
            let value = UInt32(archiveValue.dropFirst(), radix: 16)
        else { return nil }
        red = UInt8((value >> 16) & 255)
        green = UInt8((value >> 8) & 255)
        blue = UInt8(value & 255)
        alpha = bytes.count == 9 ? UInt8(value >> 24) : 255
    }

    /// Canonical source notation for a genuine edit; semantic no-ops retain original bytes instead.
    public var archiveValue: String {
        let channels = alpha == 255 ? [red, green, blue] : [alpha, red, green, blue]
        return "#"
            + channels.map {
                let text = String($0, radix: 16, uppercase: true)
                return text.count == 1 ? "0" + text : text
            }.joined()
    }
}

/// Preserve absence and unsupported source spelling independently from a valid color.
public enum ComponentColorValue: Equatable, Sendable {
    /// No explicit source color; generation determines its fallback.
    case unset
    case value(DocumentColor)
    case unsupported(String)
}
