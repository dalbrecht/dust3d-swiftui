/// Visible corner and edge handles for a crop rectangle in displayed image coordinates.
public enum ReferenceCropHandle: CaseIterable, Hashable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// A gesture chooses its operation once, from its initial location and the selected tool.
public enum ReferenceCropInteraction: Equatable, Sendable {
    case draw
    case move
    case resize(ReferenceCropHandle)
}

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

    /// Locate an edge/corner handle in preview points, including letterbox offsets.
    /// - Parameters:
    ///   - handle: Edge or corner on the displayed rectangle.
    ///   - crop: Validated crop matching this projection's source dimensions.
    /// - Returns: Handle center in the same coordinate system as pointer input.
    /// - Throws: `ReferenceCompositionError.invalidCrop` for mismatched source dimensions.
    public func handlePoint(_ handle: ReferenceCropHandle, crop: ReferenceImageCrop) throws -> CanvasPoint {
        guard crop.size == size else { throw ReferenceCompositionError.invalidCrop }
        let left = imageX + Double(crop.x) * scale
        let top = imageY + Double(crop.y) * scale
        let right = left + Double(crop.width) * scale
        let bottom = top + Double(crop.height) * scale
        let centerX = (left + right) / 2
        let centerY = (top + bottom) / 2
        switch handle {
        case .topLeft: return .init(x: left, y: top)
        case .top: return .init(x: centerX, y: top)
        case .topRight: return .init(x: right, y: top)
        case .right: return .init(x: right, y: centerY)
        case .bottomRight: return .init(x: right, y: bottom)
        case .bottom: return .init(x: centerX, y: bottom)
        case .bottomLeft: return .init(x: left, y: bottom)
        case .left: return .init(x: left, y: centerY)
        }
    }

    /// Pick a resize handle, move an interior rectangle, or draw outside it.
    /// - Parameters:
    ///   - point: Initial finite pointer position in preview coordinates.
    ///   - crop: Displayed crop matching this source.
    ///   - isAdjusting: False preserves unrestricted new-selection drawing.
    /// - Returns: Stable operation for the entire gesture. Hit regions shrink for small crops to avoid overlap.
    /// - Throws: `ReferenceCompositionError.invalidCrop` for invalid input/source identity.
    public func interaction(at point: CanvasPoint, crop: ReferenceImageCrop, isAdjusting: Bool) throws
        -> ReferenceCropInteraction
    {
        guard point.x.isFinite, point.y.isFinite, crop.size == size else { throw ReferenceCompositionError.invalidCrop }
        guard isAdjusting else { return .draw }
        let radius = min(20, Double(crop.width) * scale / 4, Double(crop.height) * scale / 4)
        for handle in ReferenceCropHandle.allCases {
            let center = try handlePoint(handle, crop: crop)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = dx * dx + dy * dy
            if distance <= radius * radius { return .resize(handle) }
        }
        let topLeft = try handlePoint(.topLeft, crop: crop)
        let bottomRight = try handlePoint(.bottomRight, crop: crop)
        return (topLeft.x...bottomRight.x).contains(point.x) && (topLeft.y...bottomRight.y).contains(point.y)
            ? .move : .draw
    }

    /// Apply pointer displacement while retaining the grabbed edge offset and stationary boundaries.
    /// - Parameters:
    ///   - original: Immutable displayed crop captured at gesture start.
    ///   - interaction: Operation chosen at gesture start.
    ///   - start: Initial finite pointer position.
    ///   - end: Current/final finite pointer position.
    /// - Returns: A source-contained crop; moving preserves its extent and resizing keeps at least one pixel.
    /// - Throws: `ReferenceCompositionError.invalidCrop` for invalid points/source or empty new selection.
    public func adjust(
        _ original: ReferenceImageCrop, interaction: ReferenceCropInteraction, from start: CanvasPoint,
        to end: CanvasPoint
    ) throws -> ReferenceImageCrop {
        guard original.size == size, [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else {
            throw ReferenceCompositionError.invalidCrop
        }
        func pixel(_ value: Double, offset: Double, maximum: Int) -> Int {
            // Bound normalized points before conversion/subtraction, including finite inputs whose quotient overflows.
            Int(min(2 * Double(maximum), max(-Double(maximum), (value - offset) / scale)).rounded())
        }
        let dx = pixel(end.x, offset: imageX, maximum: size.width) - pixel(start.x, offset: imageX, maximum: size.width)
        let dy =
            pixel(end.y, offset: imageY, maximum: size.height) - pixel(start.y, offset: imageY, maximum: size.height)
        switch interaction {
        case .draw:
            return try crop(from: start, to: end)
        case .move:
            return try .init(
                size: size, x: min(size.width - original.width, max(0, original.x + dx)),
                y: min(size.height - original.height, max(0, original.y + dy)), width: original.width,
                height: original.height)
        case .resize(let handle):
            var left = original.x
            var top = original.y
            var right = left + original.width
            var bottom = top + original.height
            if handle == .topLeft || handle == .left || handle == .bottomLeft {
                left = min(right - 1, max(0, left + dx))
            }
            if handle == .topRight || handle == .right || handle == .bottomRight {
                right = max(left + 1, min(size.width, right + dx))
            }
            if handle == .topLeft || handle == .top || handle == .topRight { top = min(bottom - 1, max(0, top + dy)) }
            if handle == .bottomLeft || handle == .bottom || handle == .bottomRight {
                bottom = max(top + 1, min(size.height, bottom + dy))
            }
            return try .init(size: size, x: left, y: top, width: right - left, height: bottom - top)
        }
    }
}
