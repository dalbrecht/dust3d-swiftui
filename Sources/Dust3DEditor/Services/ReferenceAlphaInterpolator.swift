import CoreGraphics
import Foundation

/// Resample small straight-alpha profiles in 16-bit premultiplied space.
enum ReferenceAlphaInterpolator {
    private typealias Pixel = SIMD4<Int>
    private static let unit = 1 << 16

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
                    let channels = Pixel(Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]), 255)
                    let premultiplied =
                        source.isIndexed
                        ? divideBy255(channels &* Pixel(repeating: alpha))
                        : (channels &* Pixel(repeating: alpha * 257) &+ Pixel(repeating: 127)) / 255
                    pixels.append(premultiplied)
                }
            }
            return pixels
        }

        let inverseScale = Double(crop.height) / Double(height)
        let step = Int(inverseScale * Double(unit))
        let horizontal = (0..<width).map { column in
            Coordinate(position: step / 2 - unit / 2 + column * step, limit: crop.width)
        }
        let boundary = Double(crop.width) / inverseScale - Double(width - 1)
        let geometricCoverage = min(255, max(0, Int(boundary * 255)))
        let edgeCoverage =
            source.isIndexed && geometricCoverage < 255
            ? max(0, geometricCoverage - 1) : geometricCoverage
        let fractionMask = source.isIndexed ? 0xFF00 : 0xFFFF
        let vectorWidth = width - width % 4
        var output = Data(count: width * height * 4)
        try output.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for row in 0..<height {
                try Task.checkCancellation()
                let y = Coordinate(
                    position: Int((Double(row) + 0.5) * inverseScale * Double(unit)) - unit / 2,
                    limit: crop.height)
                for (column, x) in horizontal.enumerated() {
                    let top = y.first * crop.width
                    let bottom = y.second * crop.width
                    let left = interpolate(
                        pixels[top + x.first], pixels[bottom + x.first], fraction: y.fraction & fractionMask)
                    let right = interpolate(
                        pixels[top + x.second], pixels[bottom + x.second], fraction: y.fraction & fractionMask)
                    var pixel = interpolate(left, right, fraction: x.fraction & fractionMask)
                    if column == width - 1 && edgeCoverage < 255 {
                        let covered = pixel &* Pixel(repeating: edgeCoverage)
                        pixel =
                            source.isIndexed
                            ? divideBy255(covered) : (covered &+ Pixel(repeating: 127)) / 255
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

    private static func divideBy255(_ value: Pixel) -> Pixel {
        (value &+ (value &>> 8) &+ Pixel(repeating: 128)) &>> 8
    }

    private static func interpolate(_ first: Pixel, _ second: Pixel, fraction: Int) -> Pixel {
        ((first &* Pixel(repeating: unit - fraction)) &+ (second &* Pixel(repeating: fraction))) &>> 16
    }
}
