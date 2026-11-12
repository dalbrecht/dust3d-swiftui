import CoreGraphics
import Foundation

/// Smooth resampling for opaque 8-bit reference crops, matching the Qt 6.8 raster convention.
enum FixedPointReferenceScaler {
    private static let positionUnit = 1 << 16
    private static let interpolationUnit = 1 << 8
    private static let areaUnit = 1 << 14

    private typealias Pixel = SIMD4<Int>

    private struct Sample {
        let index: Int
        let weight: Int
    }

    static func scale(_ image: CGImage, width: Int, height: Int, isMirrored: Bool) throws -> CGImage {
        let sourceWidth = image.width
        let sourceHeight = image.height
        if sourceWidth == width && sourceHeight == height && !isMirrored { return image }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: sourceWidth, height: sourceHeight,
                bitsPerComponent: 8, bytesPerRow: sourceWidth * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
            let source = context.data?.assumingMemoryBound(to: UInt8.self)
        else { throw ReferenceImageError.conversionFailed }

        if isMirrored {
            context.translateBy(x: CGFloat(sourceWidth), y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        let horizontal = samples(source: sourceWidth, destination: width)
        let vertical = samples(source: sourceHeight, destination: height)
        let reducesWidth = width < sourceWidth
        let reducesHeight = height < sourceHeight
        var output = Data(count: width * height * 4)
        try output.withUnsafeMutableBytes { rawOutput in
            let bytes = rawOutput.bindMemory(to: UInt8.self)
            for (y, rows) in vertical.enumerated() {
                try Task.checkCancellation()
                for (x, columns) in horizontal.enumerated() {
                    let pixel: Pixel
                    switch (reducesWidth, reducesHeight) {
                    case (false, false):
                        pixel =
                            columns.reduce(Pixel.zero) { total, column in
                                total
                                    &+ ((weighted(
                                        rows, base: column.index, stride: sourceWidth, source: source)
                                        &>> 8) &* Pixel(repeating: column.weight))
                            } &>> 8
                    case (true, true):
                        pixel =
                            rows.reduce(Pixel.zero) { total, row in
                                total
                                    &+ ((weighted(
                                        columns, base: row.index * sourceWidth, stride: 1, source: source)
                                        &>> 4) &* Pixel(repeating: row.weight))
                            } &>> 24
                    case (true, false):
                        pixel =
                            rows.reduce(Pixel.zero) { total, row in
                                total
                                    &+ (weighted(
                                        columns, base: row.index * sourceWidth, stride: 1, source: source)
                                        &* Pixel(repeating: row.weight))
                            } &>> 22
                    case (false, true):
                        pixel =
                            columns.reduce(Pixel.zero) { total, column in
                                total
                                    &+ (weighted(
                                        rows, base: column.index, stride: sourceWidth, source: source)
                                        &* Pixel(repeating: column.weight))
                            } &>> 22
                    }
                    let offset = (y * width + x) * 4
                    bytes[offset] = UInt8(pixel.x)
                    bytes[offset + 1] = UInt8(pixel.y)
                    bytes[offset + 2] = UInt8(pixel.z)
                    bytes[offset + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: output as CFData),
            let result = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw ReferenceImageError.conversionFailed }
        return result
    }

    private static func weighted(
        _ samples: [Sample], base: Int, stride: Int, source: UnsafePointer<UInt8>
    ) -> Pixel {
        samples.reduce(Pixel.zero) { total, sample in
            let offset = (base + sample.index * stride) * 4
            let pixel = Pixel(
                Int(source[offset]), Int(source[offset + 1]), Int(source[offset + 2]),
                0)
            return total &+ (pixel &* Pixel(repeating: sample.weight))
        }
    }

    private static func samples(source: Int, destination: Int) -> [[Sample]] {
        let step = source * positionUnit / destination
        if destination >= source {
            let start = source * (positionUnit / 2) / destination - positionUnit / 2
            return (0..<destination).map { index in
                let position = start + index * step
                let cell = position >> 16
                let left = min(max(cell, 0), source - 1)
                if cell < 0 || cell >= source - 1 {
                    return [Sample(index: left, weight: interpolationUnit)]
                }
                let fraction = (position & (positionUnit - 1)) >> 8
                return [
                    Sample(index: left, weight: interpolationUnit - fraction),
                    Sample(index: left + 1, weight: fraction),
                ]
            }
        }
        let fullWeight = (destination * areaUnit + source - 1) / source
        return (0..<destination).map { index in
            let position = index * step
            let cell = position >> 16
            let firstWeight = (positionUnit - (position & (positionUnit - 1))) * fullWeight / positionUnit
            var result = [Sample(index: cell, weight: firstWeight)]
            var remaining = areaUnit - firstWeight
            while remaining > 0 {
                let weight = min(fullWeight, remaining)
                result.append(Sample(index: min(cell + result.count, source - 1), weight: weight))
                remaining -= weight
            }
            return result
        }
    }
}
