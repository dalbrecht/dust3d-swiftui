import Dust3DDocument

/// Invalid reference-image dimensions, crop geometry or composed output.
public enum ReferenceCompositionError: Error, Equatable, Sendable {
    case invalidDimensions
    case invalidCrop
    case emptyComposition
    case outputTooLarge
}

/// Validated pixel dimensions shared by the crop model and raster boundary.
public struct ReferencePixelSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    /// - Parameters:
    ///   - width: Positive pixel width, at most 8192.
    ///   - height: Positive pixel height, at most 8192; total pixels must not exceed 16 Mi.
    /// - Throws: `ReferenceCompositionError.invalidDimensions` for unsupported dimensions.
    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= 8192, height <= 8192, width <= 16 * 1024 * 1024 / height else {
            throw ReferenceCompositionError.invalidDimensions
        }
        self.width = width
        self.height = height
    }
}

/// Half-open pixel crop in an orientation-normalized source, with top-left origin.
public struct ReferenceImageCrop: Equatable, Sendable {
    public let size: ReferencePixelSize
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    /// Select the whole validated source image. See the model README for composition examples.
    public init(size: ReferencePixelSize) {
        self.size = size
        x = 0
        y = 0
        width = size.width
        height = size.height
    }

    /// Construct a nonempty crop entirely contained in the source.
    /// - Parameters:
    ///   - size: Validated source dimensions.
    ///   - x: Left pixel boundary.
    ///   - y: Top pixel boundary.
    ///   - width: Positive number of columns.
    ///   - height: Positive number of rows.
    /// - Throws: `ReferenceCompositionError.invalidCrop` without clamping invalid numeric input.
    public init(size: ReferencePixelSize, x: Int, y: Int, width: Int, height: Int) throws {
        guard x >= 0, y >= 0, x < size.width, y < size.height,
            width > 0, height > 0, width <= size.width - x, height <= size.height - y
        else { throw ReferenceCompositionError.invalidCrop }
        self.size = size
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Normalize/clamp pointer endpoints before subtraction, including extreme integer inputs.
    /// - Parameters:
    ///   - x1: First horizontal boundary.
    ///   - y1: First vertical boundary.
    ///   - x2: Opposite horizontal boundary.
    ///   - y2: Opposite vertical boundary.
    ///   - size: Validated source dimensions.
    /// - Returns: A contained crop using half-open pixel boundaries.
    /// - Throws: `ReferenceCompositionError.invalidCrop` for an empty clamped rectangle.
    public static func between(x1: Int, y1: Int, x2: Int, y2: Int, size: ReferencePixelSize) throws -> Self {
        let left = min(max(0, x1), size.width)
        let right = min(max(0, x2), size.width)
        let top = min(max(0, y1), size.height)
        let bottom = min(max(0, y2), size.height)
        return try Self(
            size: size, x: min(left, right), y: min(top, bottom), width: abs(right - left), height: abs(bottom - top))
    }

    /// Crop coordinates after mirroring the entire source horizontally; the selected pixels stay associated.
    public var mirroredHorizontally: Self {
        // This transformation preserves every invariant established by the checked initializer.
        Self(size: size, mirrored: self)
    }

    private init(size: ReferencePixelSize, mirrored crop: Self) {
        self.size = size
        x = size.width - crop.x - crop.width
        y = crop.y
        width = crop.width
        height = crop.height
    }
}

/// Qt-shaped white turnaround canvas, with 512-pixel profile height and independently centered halves.
public struct ReferenceCompositionLayout: Equatable, Sendable {
    /// Placement of a cropped source scaled to the composition height.
    public struct Placement: Equatable, Sendable {
        public let x: Int
        public let width: Int
    }
    public let width: Int
    public let height: Int
    public let front: Placement?
    public let side: Placement?
    public let origin: NodePosition

    /// Compute layout without allocating pixels or changing document state.
    /// - Parameters:
    ///   - front: Optional Front crop, placed in the left half.
    ///   - side: Optional Side crop, placed in the right half.
    /// - Throws: Typed composition errors for empty input or output wider than 8192 pixels.
    /// - Note: Widths round to the nearest pixel, with a minimum of one for extremely thin crops.
    /// See the model README for an example.
    public init(front: ReferenceImageCrop?, side: ReferenceImageCrop?) throws {
        guard front != nil || side != nil else { throw ReferenceCompositionError.emptyComposition }
        let frontWidth = front.map { max(1, ($0.width * 512 + $0.height / 2) / $0.height) }
        let sideWidth = side.map { max(1, ($0.width * 512 + $0.height / 2) / $0.height) }
        let canvasWidth = max(1024, max(frontWidth ?? 0, sideWidth ?? 0) * 2)
        guard canvasWidth <= 8192 else { throw ReferenceCompositionError.outputTooLarge }
        let half = canvasWidth / 2
        let frontPlacement = frontWidth.map { Placement(x: (half - $0) / 2, width: $0) }
        let sidePlacement = sideWidth.map { Placement(x: half + (half - $0) / 2, width: $0) }
        self.front = frontPlacement
        self.side = sidePlacement
        width = canvasWidth
        height = 512
        origin = NodePosition(
            x: frontPlacement.map { (Double($0.x) + Double($0.width) / 2) / 512 } ?? Double(half) / 1024,
            y: 0.5,
            z: sidePlacement.map { (Double($0.x) + Double($0.width) / 2) / 512 } ?? Double(half) * 1.5 / 512)
    }
}
