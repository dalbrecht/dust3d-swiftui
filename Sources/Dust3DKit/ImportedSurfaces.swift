/// Numerical source RGB encoding; alpha is always linear and straight.
public enum ImportedSurfaceColorEncoding: Sendable, Equatable { case sRGB, linear }

/// Catalog membership only; generated does not establish unique Boolean provenance.
public enum ImportedSurfaceComponentKind: Sendable, Equatable { case original, generated }

/// Opaque copied component identity, compared as exact UTF-8 bytes.
public struct ImportedSurfaceComponent: Sendable, Equatable {
    public let id: String
    public let kind: ImportedSurfaceComponentKind

    /// Compare catalog membership and original identity bytes.
    /// - Parameters: lhs and rhs are independent copied component entries.
    /// - Returns: True only when kind and UTF-8 identity match.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.id.utf8.elementsEqual(rhs.id.utf8)
    }
}

/// Straight source RGBA in expanded triangle corner order, without material factors.
public struct ImportedSurfaceColors: Sendable, Equatable {
    public let first: SIMD4<Double>
    public let second: SIMD4<Double>
    public let third: SIMD4<Double>
}

/// Source facts for one exported triangle; optional UVs may repeat outside 0–1.
public struct ImportedSurfaceTriangle: Sendable, Equatable {
    public let sourceUVs: MeshUvCorners?
    public let colors: ImportedSurfaceColors
    public let colorEncoding: ImportedSurfaceColorEncoding
    public let modelIndex: Int?
    public let componentIndex: Int?
}

/// Independent immutable geometry and aligned source records. No native pointers escape.
public struct ImportedSurfaceMesh: Sendable {
    public let mesh: Mesh
    public let triangles: [ImportedSurfaceTriangle]
    public let modelIDs: [String]
    public let components: [ImportedSurfaceComponent]
    public let nativePayloadBytes: Int
    /// Copied record/array capacities, identity bytes and warning bytes; excludes workspace/allocator overhead.
    public let copiedPayloadBytes: Int
}

/// Independent native and Swift retained-data quotas, validated before generation.
public struct ImportedSurfaceOptions: Sendable {
    public let maximumNativePayloadBytes: Int
    public let maximumCopiedPayloadBytes: Int

    /// Configure output ownership, separate from decoder/generator working memory.
    /// - Parameters:
    ///   - maximumNativePayloadBytes: Zero selects 64 MiB; maximum 256 MiB.
    ///   - maximumCopiedPayloadBytes: Positive Swift copy budget up to 256 MiB, default 64 MiB.
    public init(maximumNativePayloadBytes: Int = 0, maximumCopiedPayloadBytes: Int = 64 * 1024 * 1024) {
        self.maximumNativePayloadBytes = maximumNativePayloadBytes
        self.maximumCopiedPayloadBytes = maximumCopiedPayloadBytes
    }
}

/// Swift boundary failures remain distinct from original native generation errors.
public enum ImportedSurfaceError: Error, Sendable, Equatable, CaseIterable {
    case invalidLimits, archiveLimitExceeded, copyLimitExceeded, invalidNativeCounts
    case invalidIdentity, invalidComponent, invalidTriangle
}
