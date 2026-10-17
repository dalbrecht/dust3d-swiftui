/// Interpretation of a component association, independent of UV chart applicability.
public enum MeshUvComponentKind: Sendable, Equatable {
    case unknown
    case component
    case ambiguous
    /// Preserve a future native interpretation without guessing its meaning.
    case unrecognized(UInt32)

    init(rawValue: UInt32) {
        switch rawValue {
        case 0: self = .unknown
        case 1: self = .component
        case 2: self = .ambiguous
        default: self = .unrecognized(rawValue)
        }
    }
}

/// Exact original component key. Engine identity is byte-exact, unlike Swift String equality.
public struct MeshUvComponentIdentity: Sendable, Equatable {
    public let componentID: String

    /// Compare exact original UTF-8 bytes without Unicode or UUID normalization.
    /// - Parameters: lhs and rhs are copied original identities.
    /// - Returns: True only for byte-identical component keys.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.componentID.utf8.elementsEqual(rhs.componentID.utf8)
    }
}

/// A bounded original identity index or an explicit unresolved association.
public struct MeshUvComponentReference: Sendable, Equatable {
    public let kind: MeshUvComponentKind
    public let identityIndex: Int?
}

/// UVs in actual exported triangle corner order; stored without a per-triangle heap array.
public struct MeshUvCorners: Sendable, Equatable {
    public let first: SIMD2<Double>
    public let second: SIMD2<Double>
    public let third: SIMD2<Double>
}

/// One retained triangle. A mapping does not establish unique Boolean material ownership.
public struct MeshUvTriangle: Sendable, Equatable {
    public let corners: MeshUvCorners
    public let hasMapping: Bool
    public let component: MeshUvComponentReference
}

/// Chart metadata only: no decoded or baked pixels and no color-space conversion.
public struct MeshUvChart: Sendable, Equatable {
    public let origin: SIMD2<Double>
    public let size: SIMD2<Double>
    public let color: SIMD4<Double>
    public let isFlipped: Bool
    public let component: MeshUvComponentReference
    /// Nil for solid or gradient charts. Engine-canonical identity for image charts.
    public let imageID: String?

    /// Compare engine image keys byte-for-byte, preserving distinct Unicode spellings.
    /// - Parameters: lhs and rhs are copied chart records.
    /// - Returns: True only when all numeric fields, source references and identity bytes match.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.origin == rhs.origin, lhs.size == rhs.size, lhs.color == rhs.color,
            lhs.isFlipped == rhs.isFlipped, lhs.component == rhs.component
        else { return false }
        switch (lhs.imageID, rhs.imageID) {
        case (.some(let first), .some(let second)): return first.utf8.elementsEqual(second.utf8)
        case (.none, .none): return true
        default: return false
        }
    }
}

/// Horizontal seam descriptor associated by chart ordinal, independently of source identity.
public struct MeshUvGradient: Sendable, Equatable {
    public let chartIndex: Int
    public let largeColor: SIMD4<Double>
    public let smallColor: SIMD4<Double>
    public let resolution: Int
}

/// Immutable copied UV metadata. Missing mappings and unresolved identities stay explicit.
public struct MeshUvMetadata: Sendable, Equatable {
    public let components: [MeshUvComponentIdentity]
    public let triangles: [MeshUvTriangle]
    public let charts: [MeshUvChart]
    public let gradients: [MeshUvGradient]
    /// Inherited atlas packing scale, not a baked image dimension.
    public let packedTextureSize: Double

    init(
        componentIDs: [String], triangles: [RawMeshUvTriangle], charts: [RawMeshUvChart],
        gradients: [MeshUvGradient], expandedVertexCount: Int, packedTextureSize: Double
    ) throws {
        guard expandedVertexCount > 0, expandedVertexCount.isMultiple(of: 3) else {
            throw MeshUvDataError.invalidGeometryCount
        }
        guard triangles.count == expandedVertexCount / 3 else { throw MeshUvDataError.invalidTriangleCount }
        var identities: Set<[UInt8]> = []
        for identifier in componentIDs {
            guard Self.validIdentifier(identifier), identities.insert(Array(identifier.utf8)).inserted else {
                throw MeshUvDataError.invalidIdentity
            }
        }
        guard packedTextureSize.isFinite,
            charts.isEmpty ? packedTextureSize == 0 : packedTextureSize > 0
        else { throw MeshUvDataError.invalidTextureSize }
        // Inherited rectangle packing uses float intermediates; allow only its tiny
        // edge-sum rounding error. Individual corners and channel ranges remain strict.
        let chartEdgeTolerance = 0.000001
        let copiedCharts = try charts.map { chart -> MeshUvChart in
            guard Self.validCoordinate(chart.origin), Self.validCoordinate(chart.size),
                chart.size.x > 0, chart.size.y > 0,
                chart.origin.x + chart.size.x <= 1 + chartEdgeTolerance,
                chart.origin.y + chart.size.y <= 1 + chartEdgeTolerance,
                Self.validColor(chart.color), chart.flipped <= 1
            else { throw MeshUvDataError.invalidChart }
            if let identifier = chart.imageID, !Self.validIdentifier(identifier) {
                throw MeshUvDataError.invalidIdentity
            }
            return MeshUvChart(
                origin: chart.origin, size: chart.size, color: chart.color, isFlipped: chart.flipped == 1,
                component: try Self.reference(chart.componentKind, chart.componentIndex, componentIDs.count),
                imageID: chart.imageID)
        }
        let copiedTriangles = try triangles.map { triangle -> MeshUvTriangle in
            guard triangle.known <= 1 else { throw MeshUvDataError.invalidMappingMarker }
            let corners = triangle.corners
            guard Self.validCoordinate(corners.first), Self.validCoordinate(corners.second),
                Self.validCoordinate(corners.third)
            else { throw MeshUvDataError.invalidCoordinate }
            if triangle.known == 0 {
                guard corners.first == .zero, corners.second == .zero, corners.third == .zero else {
                    throw MeshUvDataError.invalidCoordinate
                }
            } else if copiedCharts.isEmpty {
                throw MeshUvDataError.invalidChart
            }
            return MeshUvTriangle(
                corners: corners, hasMapping: triangle.known == 1,
                component: try Self.reference(triangle.componentKind, triangle.componentIndex, componentIDs.count))
        }
        var gradientCharts: Set<Int> = []
        for gradient in gradients {
            guard copiedCharts.indices.contains(gradient.chartIndex),
                gradientCharts.insert(gradient.chartIndex).inserted,
                copiedCharts[gradient.chartIndex].imageID == nil,
                (1...8192).contains(gradient.resolution),
                Self.validColor(gradient.largeColor), Self.validColor(gradient.smallColor)
            else { throw MeshUvDataError.invalidGradient }
        }
        self.components = componentIDs.map { MeshUvComponentIdentity(componentID: $0) }
        self.triangles = copiedTriangles
        self.charts = copiedCharts
        self.gradients = gradients
        self.packedTextureSize = packedTextureSize
    }

    private static func validCoordinate(_ value: SIMD2<Double>) -> Bool {
        (0..<2).allSatisfy { value[$0].isFinite && (0...1).contains(value[$0]) }
    }

    private static func validColor(_ value: SIMD4<Double>) -> Bool {
        (0..<4).allSatisfy { value[$0].isFinite && (0...1).contains(value[$0]) }
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 38 && !value.utf8.contains(0)
    }

    private static func reference(_ rawKind: UInt32, _ index: Int, _ count: Int) throws
        -> MeshUvComponentReference
    {
        let kind = MeshUvComponentKind(rawValue: rawKind)
        let isValidIndex = index >= 0 && index < count
        switch kind {
        case .component:
            guard isValidIndex else { throw MeshUvDataError.invalidComponentIdentity }
        case .unknown, .ambiguous:
            guard index == -1 else { throw MeshUvDataError.invalidComponentIdentity }
        case .unrecognized:
            guard index == -1 || isValidIndex else { throw MeshUvDataError.invalidComponentIdentity }
        }
        return MeshUvComponentReference(kind: kind, identityIndex: index == -1 ? nil : index)
    }
}

struct RawMeshUvTriangle {
    let corners: MeshUvCorners
    let known: UInt8
    let componentKind: UInt32
    let componentIndex: Int
}

struct RawMeshUvChart {
    let origin: SIMD2<Double>
    let size: SIMD2<Double>
    let color: SIMD4<Double>
    let flipped: UInt8
    let componentKind: UInt32
    let componentIndex: Int
    let imageID: String?
}

enum MeshUvDataError: Error, Equatable {
    case invalidGeometryCount
    case invalidTriangleCount
    case invalidIdentity
    case invalidMappingMarker
    case invalidCoordinate
    case invalidComponentIdentity
    case invalidChart
    case invalidGradient
    case invalidTextureSize
    case invalidBufferCounts
}
