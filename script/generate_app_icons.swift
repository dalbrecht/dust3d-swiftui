#!/usr/bin/env swift
import AppKit
import Foundation

// Placeholder artwork is intentionally simple; keep a reproducible source for later styling.
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "assets/app-icons")
let sizes = [16, 32, 128, 256, 512]
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func polygon(_ points: [NSPoint], color: NSColor) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() { path.line(to: point) }
    path.close()
    color.setFill()
    path.fill()
}

for (name, badge, background) in [
    ("Dust3DEditor", "E", NSColor(srgbRed: 0.02, green: 0.43, blue: 0.43, alpha: 1)),
    ("Dust3DViewer", "V", NSColor(srgbRed: 0.13, green: 0.31, blue: 0.65, alpha: 1)),
] {
    let iconSet = outputDirectory.appendingPathComponent("\(name).iconset")
    try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
    for size in sizes {
        for scale in [1, 2] {
            let pixels = size * scale
            guard
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
            else {
                fatalError("Cannot allocate icon bitmap")
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let transform = NSAffineTransform()
            transform.scale(by: CGFloat(pixels) / 1024)
            transform.concat()
            background.setFill()
            NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
            polygon(
                [NSPoint(x: 512, y: 820), NSPoint(x: 232, y: 660), NSPoint(x: 512, y: 500), NSPoint(x: 792, y: 660)],
                color: .white)
            polygon(
                [NSPoint(x: 232, y: 660), NSPoint(x: 512, y: 500), NSPoint(x: 512, y: 200), NSPoint(x: 232, y: 360)],
                color: NSColor(white: 0.72, alpha: 1))
            polygon(
                [NSPoint(x: 512, y: 500), NSPoint(x: 792, y: 660), NSPoint(x: 792, y: 360), NSPoint(x: 512, y: 200)],
                color: NSColor(white: 0.88, alpha: 1))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 220, weight: .heavy), .foregroundColor: background,
            ]
            (badge as NSString).draw(at: NSPoint(x: 580, y: 345), withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Cannot encode icon bitmap")
            }
            let suffix = scale == 2 ? "@2x" : ""
            try png.write(to: iconSet.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        }
    }
    print(iconSet.path)
}
