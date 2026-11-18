import CoreGraphics
import Dust3DKit
import Foundation

/// Preserve 16-bit associated channels until the composed pixel is placed on white.
enum ReferenceWideAlphaRaster {
    private typealias Pixel = SIMD4<Int>
    private static let unit = 1 << 16
    private static let maximum = unit - 1

    static func scale(
        _ source: ReferenceCompositionSource, image: CGImage, width: Int, height: Int,
        usesAreaSampling requiresAreaSampling: Bool
    ) throws -> CGImage {
        let crop = source.crop
        let layout = try ImageSampleLayout(image)
        // Qt RGBX64 always takes the smooth scaler.
        let isOpaqueRGB = image.colorSpace?.model == .rgb && image.alphaInfo != .last
        let scales = width != crop.width || height != crop.height
        let usesAreaSampling = requiresAreaSampling || (isOpaqueRGB && scales)
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
        let edges = ReferenceAlphaInterpolator.PainterEdges(
            sourceWidth: crop.width, sourceHeight: crop.height, width: width, height: height)
        let horizontal =
            usesAreaSampling
            ? FixedPointReferenceScaler.samples(source: crop.width, destination: width) : []
        let vertical =
            usesAreaSampling
            ? FixedPointReferenceScaler.samples(source: crop.height, destination: height) : []
        let first = ReferenceAlphaInterpolator.painterPosition(0.5, inverseScale: inverseScale)
        let horizontalPainter = (0..<width).map { indices(first + $0 * step, limit: crop.width) }
        let reducesWidth = width < crop.width
        let reducesHeight = height < crop.height
        let areaShift = (reducesWidth ? 14 : 8) + (reducesHeight ? 14 : 8)
        var output = Data(count: width * height * 4)
        try output.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for row in 0..<height {
                try Task.checkCancellation()
                let y = indices(
                    ReferenceAlphaInterpolator.painterPosition(Double(row) + 0.5, inverseScale: inverseScale),
                    limit: crop.height)
                for column in 0..<width {
                    let pixel: Pixel
                    if usesAreaSampling && !reducesWidth && !reducesHeight {
                        let columns = horizontal[column]
                        let rows = vertical[row]
                        let interpolatesBothAxes =
                            columns.dropFirst().contains { $0.weight > 0 }
                            && rows.dropFirst().contains { $0.weight > 0 }
                        var total = Pixel.zero
                        if interpolatesBothAxes {
                            for x in columns {
                                var verticalTotal = Pixel.zero
                                for y in rows {
                                    verticalTotal =
                                        try verticalTotal &+ sample(x.index, y.index) &* Pixel(repeating: y.weight)
                                }
                                total = total &+ (verticalTotal &>> 8) &* Pixel(repeating: x.weight)
                            }
                            total = total &>> 8
                        } else {
                            // A single-axis interpolation truncates each weighted term before addition.
                            for y in rows {
                                for x in columns {
                                    let term = try sample(x.index, y.index) &* Pixel(repeating: x.weight * y.weight)
                                    total = total &+ (term &>> 16)
                                }
                            }
                        }
                        pixel = total
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
                        let coverage = edges.coverage(right: column == width - 1, bottom: row == height - 1)
                        pixel =
                            coverage < 255
                            ? (mixed &* Pixel(repeating: coverage) &+ Pixel(repeating: 127)) / 255 : mixed
                    }
                    let offset = (row * width + column) * 4
                    for channel in 0..<3 {
                        // The opaque conversion normalizes any padding lost to interpolation truncation.
                        let value =
                            isOpaqueRGB && pixel.w != maximum
                            ? (pixel[channel] * maximum + pixel.w / 2) / pixel.w
                            : pixel[channel] + maximum - pixel.w
                        bytes[offset + channel] = UInt8((value + 128) / 257)
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
