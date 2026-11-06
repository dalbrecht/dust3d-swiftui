import Dust3DDocument
import Foundation

/// Unsupported owned pixel storage, displayed geometry or graph color ownership.
public enum ReferenceColorError: Error, Equatable, Sendable {
    case invalidRaster
    case invalidLayout
    case unresolvableOwner(String)
    case ambiguousOwner(String)
}

/// An already-fitted, orientation-normalized raster with top-left, straight RGBA8 rows.
/// The platform boundary must supply the same fitted raster used for reference sampling;
/// this value neither decodes an original image nor assumes a display backing scale.
public struct ReferenceColorRaster: Sendable {
    public let size: ReferencePixelSize
    public let rowStride: Int
    /// Independently owned immutable straight rows; returned Data values use normal value/COW semantics.
    public let pixels: Data

    /// Copy bounded caller pixels, preserving RGB even when alpha is zero.
    /// - Parameters: Dimensions use the reference-image limits; padding may separate rows.
    ///   `pixels` must include the final pixel; bounded trailing padding in the final row is optional.
    /// - Throws: `invalidRaster` before copying for invalid dimensions, stride or payload.
    public init(width: Int, height: Int, rowStride: Int, pixels: Data) throws {
        guard let size = try? ReferencePixelSize(width: width, height: height),
            rowStride >= width * 4, rowStride <= 64 * 1024 * 1024 / height
        else { throw ReferenceColorError.invalidRaster }
        let required = (height - 1) * rowStride + width * 4
        guard pixels.count >= required, pixels.count <= rowStride * height else {
            throw ReferenceColorError.invalidRaster
        }
        self.size = size
        self.rowStride = rowStride
        self.pixels = pixels.withUnsafeBytes { Data($0) }
    }

    /// Read a valid pixel without clamping outside coordinates into the image.
    /// - Returns: Straight source channels, including hidden RGB, or nil outside half-open bounds.
    public func color(x: Int, y: Int) -> DocumentColor? {
        guard x >= 0, y >= 0, x < size.width, y < size.height else { return nil }
        let offset = y * rowStride + x * 4
        return DocumentColor(
            red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2], alpha: pixels[offset + 3])
    }
}

/// Frozen whole-reference placement matching NodeCanvas's center and frame in logical view points.
/// Current native Front and Side canvases each display the entire retained composed PNG;
/// no paired-profile half-image offset or transient crop/mirror draft is applied here.
public struct ReferenceColorSamplingLayout: Sendable {
    private let origin: CanvasPoint
    private let end: CanvasPoint
    private let width: Double
    private let height: Double
    private let aspect: Double
    private let projection: CanvasProjection

    /// Capture the displayed reference rectangle before asynchronous raster preparation.
    /// - Parameters: `referenceSize` describes the retained composed image, not a crop draft;
    ///   `projection` is exactly the projection used by the source canvas.
    /// - Throws: `invalidLayout` for nonfinite, empty or absurd displayed geometry.
    public init(referenceSize: ReferencePixelSize, projection: CanvasProjection) throws {
        let aspect = Double(referenceSize.width) / Double(referenceSize.height)
        // Equivalent to NodeCanvas's projected center +/- half frame extent, but deriving
        // both corners through the same projection avoids cancellation changing edge admission.
        let origin = projection.point(for: .init(x: 0, y: 0, z: 0))
        let end = projection.point(for: .init(x: aspect, y: 1, z: aspect))
        let width = end.x - origin.x
        let height = end.y - origin.y
        // This is a geometry admission bound, not a pixel allocation or physical-screen size.
        guard
            [origin.x, origin.y, end.x, end.y, width, height].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000_000_000 }
            ),
            width > 0, height > 0
        else { throw ReferenceColorError.invalidLayout }
        self.origin = origin
        self.end = end
        self.width = width
        self.height = height
        self.aspect = aspect
        self.projection = projection
    }

    /// Sample the explicit fitted raster using nearest-cell, half-open quantization.
    /// - Parameters: `point` is canvas-local logical coordinates; `raster` declares its own
    ///   fitted pixel dimensions. Neither source pixels nor an implicit Retina multiplier are substituted.
    /// - Returns: Nil outside the displayed reference or for nonfinite input; never clamps to an edge pixel.
    public func color(at point: CanvasPoint, in raster: ReferenceColorRaster) -> DocumentColor? {
        guard point.x.isFinite, point.y.isFinite,
            point.x >= origin.x, point.y >= origin.y, point.x < end.x, point.y < end.y
        else { return nil }
        let x = (point.x - origin.x) / width
        let y = (point.y - origin.y) / height
        guard x.isFinite, y.isFinite, x >= 0, y >= 0, x < 1, y < 1 else { return nil }
        return raster.color(
            x: Int((x * Double(raster.size.width)).rounded(.down)),
            y: Int((y * Double(raster.size.height)).rounded(.down)))
    }

    /// Project a graph sample through the same frozen Front/Side mapping as its displayed marker.
    public func color(for position: NodePosition, in raster: ReferenceColorRaster) -> DocumentColor? {
        let horizontal = projection.plane == .front ? position.x : position.z
        guard horizontal.isFinite, position.y.isFinite,
            horizontal >= 0, horizontal < aspect, position.y >= 0, position.y < 1
        else { return nil }
        return color(at: projection.point(for: position), in: raster)
    }
}
