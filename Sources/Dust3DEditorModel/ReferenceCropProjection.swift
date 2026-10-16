/// Aspect-fit mapping from a crop preview's points into top-left, half-open pixel boundaries.
public struct ReferenceCropProjection: Sendable {
    public let imageX: Double
    public let imageY: Double
    public let imageWidth: Double
    public let imageHeight: Double
    private let size: ReferencePixelSize
    private let scale: Double

    /// - Parameters:
    ///   - size: Validated orientation-normalized source dimensions.
    ///   - width: Finite preview width in 1...1,000,000 points.
    ///   - height: Finite preview height in 1...1,000,000 points.
    /// - Throws: `ReferenceCompositionError.invalidDimensions` for unusable viewport geometry.
    public init(size: ReferencePixelSize, width: Double, height: Double) throws {
        guard width.isFinite, height.isFinite, (1...1_000_000).contains(width), (1...1_000_000).contains(height) else {
            throw ReferenceCompositionError.invalidDimensions
        }
        self.size = size
        scale = min(width / Double(size.width), height / Double(size.height))
        imageWidth = Double(size.width) * scale
        imageHeight = Double(size.height) * scale
        imageX = (width - imageWidth) / 2
        imageY = (height - imageHeight) / 2
    }

    /// Normalize a drag and clamp letterbox/outside points to the image before checked integer conversion.
    /// - Parameters:
    ///   - start: Initial point in this preview's coordinate space.
    ///   - end: Current or final point in the same space.
    /// - Returns: Nonempty pixel crop; directions are interchangeable.
    /// - Throws: `ReferenceCompositionError.invalidCrop` for nonfinite points or empty rounded selection.
    public func crop(from start: CanvasPoint, to end: CanvasPoint) throws -> ReferenceImageCrop {
        guard [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else {
            throw ReferenceCompositionError.invalidCrop
        }
        func pixel(_ value: Double, offset: Double, maximum: Int) -> Int {
            Int(min(Double(maximum), max(0, (value - offset) / scale)).rounded())
        }
        return try .between(
            x1: pixel(start.x, offset: imageX, maximum: size.width),
            y1: pixel(start.y, offset: imageY, maximum: size.height),
            x2: pixel(end.x, offset: imageX, maximum: size.width),
            y2: pixel(end.y, offset: imageY, maximum: size.height), size: size)
    }
}
