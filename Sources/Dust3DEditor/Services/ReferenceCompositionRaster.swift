import CoreGraphics
import Dust3DEditorModel
import Foundation

/// Immutable raster source; crop coordinates refer to orientation-normalized pixels.
struct ReferenceCompositionSource: Sendable {
    let image: CGImage
    let crop: ReferenceImageCrop
    let isMirrored: Bool

    init(image: CGImage, crop: ReferenceImageCrop, isMirrored: Bool = false) throws {
        guard image.width == crop.size.width, image.height == crop.size.height else {
            throw ReferenceCompositionError.invalidDimensions
        }
        self.image = image
        self.crop = crop
        self.isMirrored = isMirrored
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
}
