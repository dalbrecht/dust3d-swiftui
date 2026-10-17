import AppKit
import Dust3DDocument
import SwiftUI

/// Native color-space conversion stays outside the framework-free archive value.
@MainActor enum DocumentColorPresentation {
    static func color(_ value: DocumentColor) -> Color {
        Color(
            .sRGB, red: Double(value.red) / 255, green: Double(value.green) / 255,
            blue: Double(value.blue) / 255, opacity: Double(value.alpha) / 255)
    }

    static func value(from color: Color) -> DocumentColor? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB),
            let red = channel(Double(converted.redComponent)),
            let green = channel(Double(converted.greenComponent)),
            let blue = channel(Double(converted.blueComponent)),
            let alpha = channel(Double(converted.alphaComponent))
        else { return nil }
        return DocumentColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    static func channel(_ value: Double) -> UInt8? {
        guard value.isFinite, (0...1).contains(value) else { return nil }
        return UInt8((value * 255).rounded())
    }
}
