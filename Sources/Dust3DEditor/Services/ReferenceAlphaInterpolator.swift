import CoreGraphics
import Foundation

/// Resample small straight-alpha profiles in 16-bit premultiplied space.
enum ReferenceAlphaInterpolator {
    private typealias Pixel = SIMD4<Int>
    private static let unit = 1 << 16

    // The Qt raster transform subtracts a single 16.16 unit before sampling.
    static func painterPosition(_ coordinate: Double, inverseScale: Double) -> Int {
        Int(coordinate * inverseScale * Double(unit) - 1) - unit / 2
    }

    private struct Coordinate {
        let first: Int
        let second: Int
        let fraction: Int

        init(position: Int, limit: Int) {
            let cell = position >> 16
            first = min(max(cell, 0), limit - 1)
            second = min(max(cell + 1, 0), limit - 1)
            fraction = position & (unit - 1)
        }
    }

    static func scale(
        _ source: ReferenceCompositionSource, straight: Data, width: Int, height: Int
    ) throws -> CGImage {
        let crop = source.crop
        if width == crop.width && height == crop.height {
            return try compositeUnscaled(source, straight: straight)
        }
        let pixels = try straight.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var pixels = [Pixel]()
            pixels.reserveCapacity(crop.width * crop.height)
            for row in 0..<crop.height {
                try Task.checkCancellation()
                for column in 0..<crop.width {
                    let x = crop.x + (source.isMirrored ? crop.width - 1 - column : column)
                    let offset = ((crop.y + row) * crop.size.width + x) * 4
                    let alpha = Int(bytes[offset + 3])
                    let channels = Pixel(Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]), alpha)
                    if source.isIndexed {
                        let associated = divideBy255(
                            Pixel(channels.x, channels.y, channels.z, 255) &* Pixel(repeating: alpha))
                        pixels.append(associated)
                    } else {
                        pixels.append(channels)
                    }
                }
            }
            return pixels
        }

        let inverseScale = Double(crop.height) / Double(height)
        let step = Int(inverseScale * Double(unit))
        let horizontal = (0..<width).map { column in
            Coordinate(
                position: painterPosition(0.5, inverseScale: inverseScale) + column * step, limit: crop.width)
        }
        let edges = PainterEdges(sourceWidth: crop.width, sourceHeight: crop.height, width: width, height: height)
        let fractionMask = source.isIndexed ? 0xFF00 : 0xFFFF
        let vectorWidth = width - width % 4
        var output = Data(count: width * height * 4)
        try output.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for row in 0..<height {
                try Task.checkCancellation()
                let y = Coordinate(
                    position: painterPosition(Double(row) + 0.5, inverseScale: inverseScale),
                    limit: crop.height)
                for (column, x) in horizontal.enumerated() {
                    let top = y.first * crop.width
                    let bottom = y.second * crop.width
                    let left: Pixel
                    let right: Pixel
                    if source.isIndexed {
                        left = interpolate(
                            pixels[top + x.first], pixels[bottom + x.first], fraction: y.fraction & fractionMask)
                        right = interpolate(
                            pixels[top + x.second], pixels[bottom + x.second], fraction: y.fraction & fractionMask)
                    } else {
                        let pairedColumn = column ^ 1
                        let adjacent = pairedColumn < width ? horizontal[pairedColumn] : nil
                        let topPair = associatedPair(pixels, row: top, at: x, adjacent: adjacent)
                        let bottomPair = associatedPair(pixels, row: bottom, at: x, adjacent: adjacent)
                        left = interpolate(topPair.0, bottomPair.0, fraction: y.fraction)
                        right = interpolate(topPair.1, bottomPair.1, fraction: y.fraction)
                    }
                    var pixel = interpolate(left, right, fraction: x.fraction & fractionMask)
                    if column == width - 1 || row == height - 1 {
                        let span = edges.coverage(right: column == width - 1, bottom: row == height - 1)
                        if span < 255 {
                            if source.isIndexed {
                                pixel = divideBy255(pixel &* Pixel(repeating: (span * 255) >> 8))
                            } else {
                                pixel = (pixel &* Pixel(repeating: span) &+ Pixel(repeating: 127)) / 255
                            }
                        }
                    }
                    let offset = (row * width + column) * 4
                    if source.isIndexed {
                        for channel in 0..<3 {
                            bytes[offset + channel] = UInt8(pixel[channel] + 255 - pixel.w)
                        }
                        bytes[offset + 3] = 255
                        continue
                    }
                    let alpha = (pixel.w + 128) / 257
                    for channel in 0..<3 {
                        let straight = pixel.w == 0 ? 0 : min(65535, (pixel[channel] * 65535 + pixel.w / 2) / pixel.w)
                        bytes[offset + channel] = compositeOnWhite(
                            (straight + 128) / 257, alpha: alpha, scalarTail: column >= vectorWidth)
                    }
                    bytes[offset + 3] = 255
                }
            }
        }
        return try FixedPointReferenceScaler.opaqueImage(output, width: width, height: height)
    }

    struct PainterEdges {
        let rightWidth: Int
        let bottomHeight: Int

        init(sourceWidth: Int, sourceHeight: Int, width: Int, height: Int) {
            // The antialiased painter constructs its rectangle from a clipped horizontal centerline.
            let scale = Double(height) / Double(sourceHeight)
            let horizontalExtent = Double(sourceWidth) * scale
            let clippedWidth = min(Double(width), horizontalExtent)
            let aspect = Double(sourceHeight) / Double(sourceWidth)
            let clippedAspect = aspect * sqrt(horizontalExtent * horizontalExtent / (clippedWidth * clippedWidth))
            let centerY = Double(sourceHeight) * 0.5 * scale
            let halfHeight = clippedAspect * (clippedWidth * 0.5)
            let top = centerY - halfHeight
            let bottom = centerY + halfHeight
            let right = clippedWidth * 0.5 + (0.5 * (1 / clippedAspect)) * (bottom - top)
            rightWidth = Self.partialExtent(right, limit: width)
            bottomHeight = Self.partialExtent(bottom, limit: height)
        }

        func coverage(right: Bool, bottom: Bool) -> Int {
            let column = right ? rightWidth : unit
            let row = bottom ? bottomHeight : unit
            return column * row * 255 / (unit * unit)
        }

        private static func partialExtent(_ extent: Double, limit: Int) -> Int {
            let end = Int(min(Double(limit), extent) * Double(unit))
            return max(0, end - (limit - 1) * unit)
        }
    }

    private static func compositeUnscaled(_ source: ReferenceCompositionSource, straight: Data) throws -> CGImage {
        let crop = source.crop
        let vectorWidth = crop.width - crop.width % 4
        var output = Data(count: crop.width * crop.height * 4)
        try straight.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            try output.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                for row in 0..<crop.height {
                    try Task.checkCancellation()
                    for column in 0..<crop.width {
                        let x = crop.x + (source.isMirrored ? crop.width - 1 - column : column)
                        let from = ((crop.y + row) * crop.size.width + x) * 4
                        let to = (row * crop.width + column) * 4
                        let alpha = Int(input[from + 3])
                        for channel in 0..<3 {
                            bytes[to + channel] = compositeOnWhite(
                                Int(input[from + channel]), alpha: alpha, scalarTail: column >= vectorWidth)
                        }
                        bytes[to + 3] = 255
                    }
                }
            }
        }
        return try FixedPointReferenceScaler.opaqueImage(output, width: crop.width, height: crop.height)
    }

    private static func compositeOnWhite(_ channel: Int, alpha: Int, scalarTail: Bool) -> UInt8 {
        let product = channel * alpha
        if scalarTail { return UInt8((product + 127) / 255 + 255 - alpha) }
        let rounding = product == 128 ? 128 : 127
        return UInt8(((product + (product >> 8) + rounding) >> 8) + 255 - alpha)
    }

    private static func associatedPair(
        _ pixels: [Pixel], row: Int, at coordinate: Coordinate, adjacent: Coordinate?
    ) -> (Pixel, Pixel) {
        let first = pixels[row + coordinate.first]
        let second = pixels[row + coordinate.second]
        let useVector: Bool
        if let adjacent {
            // Qt expands two adjacent bilinear pairs together. A fully opaque batch keeps
            // the full channel range instead of applying the premultiplication approximation.
            useVector = min(first.w, second.w, pixels[row + adjacent.first].w, pixels[row + adjacent.second].w) < 255
        } else {
            useVector = false
        }
        return (associate(first, useVector: useVector), associate(second, useVector: useVector))
    }

    private static func associate(_ pixel: Pixel, useVector: Bool) -> Pixel {
        let product = pixel &* Pixel(repeating: pixel.w)
        var channels =
            useVector
            ? product &+ (product &>> 7)
            : (product &* Pixel(repeating: 257) &+ Pixel(repeating: 127)) / 255
        channels.w = pixel.w * 257
        return channels
    }

    private static func divideBy255(_ value: Pixel) -> Pixel {
        (value &+ (value &>> 8) &+ Pixel(repeating: 128)) &>> 8
    }

    private static func interpolate(_ first: Pixel, _ second: Pixel, fraction: Int) -> Pixel {
        ((first &* Pixel(repeating: unit - fraction)) &+ (second &* Pixel(repeating: fraction))) &>> 16
    }
}
