/// Numerical source RGB encoding; alpha is always linear and straight.
public enum ImportedSurfaceColorEncoding: Sendable, Equatable { case sRGB, linear }

/// Catalog membership only; generated does not establish unique Boolean provenance.
public enum ImportedSurfaceComponentKind: Sendable, Hashable { case original, generated }

/// Copied component identity and its catalog membership.
public struct ImportedSurfaceComponent: Sendable, Hashable {
    public let id: ImportedSurfaceIdentity
    public let kind: ImportedSurfaceComponentKind
}

/// Opaque model/component key with byte-exact equality and hashing for material lookup.
public struct ImportedSurfaceIdentity: Sendable, Hashable {
    public let rawValue: String

    /// Preserve a bounded opaque identity without Unicode or UUID normalization.
    /// - Parameter rawValue: Nonempty UTF-8 identity, at most 38 bytes, without NUL.
    /// - Throws: ImportedSurfaceError.invalidIdentity for invalid source keys.
    /// - Example: let key = try ImportedSurfaceIdentity(rawValue: material.id).
    public init(rawValue: String) throws {
        guard !rawValue.isEmpty, rawValue.utf8.count <= 38, !rawValue.utf8.contains(0) else {
            throw ImportedSurfaceError.invalidIdentity
        }
        self.rawValue = rawValue
    }

    /// Compare original UTF-8 bytes rather than canonical Unicode equivalence.
    /// - Parameters: lhs and rhs are bounded copied model/component keys.
    /// - Returns: True only for byte-identical keys.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.utf8.elementsEqual(rhs.rawValue.utf8)
    }

    /// Hash the same UTF-8 bytes used by equality, without temporary storage.
    /// - Parameter hasher: The caller's randomized Swift hasher.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.utf8.count)
        for byte in rawValue.utf8 { hasher.combine(byte) }
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
    public let modelIDs: [ImportedSurfaceIdentity]
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
