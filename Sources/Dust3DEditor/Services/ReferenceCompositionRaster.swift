import CoreGraphics
import Dust3DEditorModel
import Foundation

/// Immutable raster source; crop coordinates refer to orientation-normalized pixels.
struct ReferenceCompositionSource: Sendable {
    let image: CGImage
    let crop: ReferenceImageCrop
    let isMirrored: Bool
    let straightRGBA: Data?
    let isIndexed: Bool
    var displayedCrop: ReferenceImageCrop { isMirrored ? crop.mirroredHorizontally : crop }

    init(
        image: CGImage, crop: ReferenceImageCrop, isMirrored: Bool = false,
        straightRGBA: Data? = nil, isIndexed: Bool = false
    ) throws {
        guard image.width == crop.size.width, image.height == crop.size.height,
            straightRGBA.map({ $0.count == image.width * image.height * 4 }) ?? true
        else {
            throw ReferenceCompositionError.invalidDimensions
        }
        self.image = image
        self.crop = crop
        self.isMirrored = isMirrored
        self.straightRGBA = straightRGBA
        self.isIndexed = isIndexed && straightRGBA != nil
    }
}

struct ReferenceCompositionResult: Sendable {
    let png: Data
    let image: CGImage
    let layout: ReferenceCompositionLayout
}

/// Call on an actor/background task; no raster allocation or encoding belongs in a SwiftUI body.
enum ReferenceCompositionRaster {
    static func compose(front: ReferenceCompositionSource?, side: ReferenceCompositionSource?) throws
        -> ReferenceCompositionResult
    {
        try Task.checkCancellation()
        let layout = try ReferenceCompositionLayout(front: front?.crop, side: side?.crop)
        try ReferenceImageCodec.validateDimensions(width: layout.width, height: layout.height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: layout.width, height: layout.height, bitsPerComponent: 8,
                bytesPerRow: layout.width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ReferenceImageError.conversionFailed }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        context.interpolationQuality = .high
        for (source, placement) in [(front, layout.front), (side, layout.side)] {
            guard let source, let placement else { continue }
            try Task.checkCancellation()
            let crop = source.crop
            guard
                let image = source.image.cropping(
                    to: CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height))
            else {
                throw ReferenceImageError.conversionFailed
            }
            let opaque =
                image.bitsPerComponent == 8 && [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
            let scales = placement.width != crop.width || layout.height != crop.height
            let usesAreaSampling =
                scales
                && (placement.width * 2 < crop.width || layout.height * 2 < crop.height
                    || crop.width * crop.height >= 1 << 20)
            let premultiplied = usesAreaSampling ? try premultipliedCrop(source) : nil
            if opaque || premultiplied != nil {
                let scaled = try FixedPointReferenceScaler.scale(
                    image, width: placement.width, height: layout.height, isMirrored: source.isMirrored,
                    premultipliedRGBA: premultiplied)
                context.draw(
                    scaled, in: CGRect(x: placement.x, y: 0, width: placement.width, height: layout.height))
                continue
            }
            if let straight = source.straightRGBA, scales || !source.isIndexed {
                let scaled = try ReferenceAlphaInterpolator.scale(
                    source, straight: straight, width: placement.width, height: layout.height)
                context.draw(scaled, in: CGRect(x: placement.x, y: 0, width: placement.width, height: layout.height))
                continue
            }
            context.saveGState()
            context.translateBy(x: CGFloat(placement.x + (source.isMirrored ? placement.width : 0)), y: 0)
            if source.isMirrored { context.scaleBy(x: -1, y: 1) }
            context.draw(image, in: CGRect(x: 0, y: 0, width: placement.width, height: layout.height))
            context.restoreGState()
        }
        guard let image = context.makeImage() else { throw ReferenceImageError.conversionFailed }
        try Task.checkCancellation()
        let png = try ReferenceImageCodec.encodePNG(image)
        try Task.checkCancellation()
        return .init(png: png, image: image, layout: layout)
    }
    private static func premultipliedCrop(_ source: ReferenceCompositionSource) throws -> Data? {
        guard let straight = source.straightRGBA else { return nil }
        let crop = source.crop
        var output = Data(count: crop.width * crop.height * 4)
        try straight.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            try output.withUnsafeMutableBytes { (pixels: UnsafeMutableRawBufferPointer) in
                for row in 0..<crop.height {
                    try Task.checkCancellation()
                    for column in 0..<crop.width {
                        let x = crop.x + (source.isMirrored ? crop.width - 1 - column : column)
                        let from = ((crop.y + row) * crop.size.width + x) * 4
                        let to = (row * crop.width + column) * 4
                        let alpha = input[from + 3]
                        for channel in 0..<3 {
                            let product = Int(input[from + channel]) * Int(alpha)
                            pixels[to + channel] = UInt8((product + (product >> 8) + 128) >> 8)
                        }
                        pixels[to + 3] = alpha
                    }
                }
            }
        }
        return output
    }
}
