import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// A template image can travel with the named choice through the native menu picker.
struct CutFacePresetIcon: View {
    let preset: CutFacePreset

    var body: some View {
        if let image = Self.images[preset] {
            Image(nsImage: image).accessibilityHidden(true)
        }
    }

    private static let images = Dictionary(
        uniqueKeysWithValues: CutFacePreset.allCases.map { ($0, makeImage(for: $0)) })

    private static func makeImage(for preset: CutFacePreset) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { @Sendable bounds in
            let points = CutFacePresetPreview.points(for: preset, width: bounds.width, height: bounds.height)
            guard let first = points.first else { return false }
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.minX + first.x, y: bounds.minY + first.y))
            for point in points.dropFirst() {
                path.line(to: NSPoint(x: bounds.minX + point.x, y: bounds.minY + point.y))
            }
            path.close()
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
