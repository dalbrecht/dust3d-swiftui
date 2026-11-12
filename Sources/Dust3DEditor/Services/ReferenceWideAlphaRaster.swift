import CoreGraphics
import Dust3DKit
import Foundation

/// Preserve 16-bit associated channels until the composed pixel is placed on white.
enum ReferenceWideAlphaRaster {
    private typealias Pixel = SIMD4<Int>
    private static let unit = 1 << 16
    private static let maximum = unit - 1

    static func scale(
        _ source: ReferenceCompositionSource, image: CGImage, width: Int, height: Int, usesAreaSampling: Bool
    ) throws -> CGImage {
        let crop = source.crop
        let layout = try ImageSampleLayout(image)
        let span = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard let data = image.dataProvider?.data, let storage = CFDataGetBytePtr(data),
            !span.overflow, image.bytesPerRow >= image.width * layout.bytesPerPixel,
            CFDataGetLength(data) >= span.partialValue
        else { throw ReferenceImageError.conversionFailed }
        defer { withExtendedLifetime(data) {} }

        func sample(_ column: Int, _ row: Int) throws -> Pixel {
            let x = crop.x + (source.isMirrored ? crop.width - 1 - column : column)
            let offset = (crop.y + row) * image.bytesPerRow + x * layout.bytesPerPixel
            let (red, green, blue, alpha) = try layout.rgba16(storage.advanced(by: offset))
            let product = Pixel(red, green, blue, maximum) &* Pixel(repeating: alpha)
            return (product &+ (product &>> 16) &+ Pixel(repeating: unit / 2)) &>> 16
        }

        let inverseScale = Double(crop.height) / Double(height)
        let step = Int(inverseScale * Double(unit))
        let boundary = Double(crop.width) / inverseScale - Double(width - 1)
        let edge = min(255, max(0, Int(boundary * 255)))
        let horizontal =
            usesAreaSampling
            ? FixedPointReferenceScaler.samples(source: crop.width, destination: width) : []
        let vertical =
            usesAreaSampling
            ? FixedPointReferenceScaler.samples(source: crop.height, destination: height) : []
        let horizontalPainter = (0..<width).map { indices(step / 2 - unit / 2 + $0 * step, limit: crop.width) }
        let reducesWidth = width < crop.width
        let reducesHeight = height < crop.height
        let areaShift = (reducesWidth ? 14 : 8) + (reducesHeight ? 14 : 8)
        var output = Data(count: width * height * 4)
        try output.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for row in 0..<height {
                try Task.checkCancellation()
                let y = indices(
                    Int((Double(row) + 0.5) * inverseScale * Double(unit)) - unit / 2, limit: crop.height)
                for column in 0..<width {
                    let pixel: Pixel
                    if usesAreaSampling && !reducesWidth && !reducesHeight {
                        var total = Pixel.zero
                        for x in horizontal[column] {
                            var verticalTotal = Pixel.zero
                            for y in vertical[row] {
                                verticalTotal =
                                    try verticalTotal &+ sample(x.index, y.index) &* Pixel(repeating: y.weight)
                            }
                            total = total &+ (verticalTotal &>> 8) &* Pixel(repeating: x.weight)
                        }
                        pixel = total &>> 8
                    } else if usesAreaSampling {
                        var total = Pixel.zero
                        for y in vertical[row] {
                            for x in horizontal[column] {
                                total = try total &+ sample(x.index, y.index) &* Pixel(repeating: x.weight * y.weight)
                            }
                        }
                        pixel = total &>> areaShift
                    } else if width == crop.width && height == crop.height {
                        pixel = try sample(column, row)
                    } else {
                        let x = horizontalPainter[column]
                        let left = try blend(sample(x.first, y.first), sample(x.first, y.second), y.fraction)
                        let right = try blend(sample(x.second, y.first), sample(x.second, y.second), y.fraction)
                        let mixed = blend(left, right, x.fraction)
                        pixel =
                            column == width - 1 && edge < 255
                            ? (mixed &* Pixel(repeating: edge) &+ Pixel(repeating: 127)) / 255 : mixed
                    }
                    let offset = (row * width + column) * 4
                    let white = maximum - pixel.w
                    for channel in 0..<3 {
                        bytes[offset + channel] = UInt8((pixel[channel] + white + 128) / 257)
                    }
                    bytes[offset + 3] = 255
                }
            }
        }
        return try FixedPointReferenceScaler.opaqueImage(output, width: width, height: height)
    }

    private static func indices(_ position: Int, limit: Int) -> (first: Int, second: Int, fraction: Int) {
        let cell = position >> 16
        return (min(max(cell, 0), limit - 1), min(max(cell + 1, 0), limit - 1), position & maximum)
    }

    private static func blend(_ a: Pixel, _ b: Pixel, _ weight: Int) -> Pixel {
        (a &* Pixel(repeating: unit - weight) &+ b &* Pixel(repeating: weight)) &>> 16
    }
}
