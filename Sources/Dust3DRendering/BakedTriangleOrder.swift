import simd

/// Opaque indices retain source order. Transparent triangles sort in view space;
/// intersecting/coplanar transparent surfaces remain a documented sorting limit.
struct BakedTriangleOrder: Sendable {
    private struct Triangle: Sendable {
        let indices: SIMD3<UInt32>
        let center: SIMD3<Float>
        let ordinal: Int
    }

    let opaqueIndices: [UInt32]
    private let transparent: [Triangle]
    var transparentIndexCount: Int { transparent.count * 3 }

    init(geometry: TexturedRenderGeometry, hasTransparentColor: Bool) throws {
        var opaque: [UInt32] = []
        var transparent: [Triangle] = []
        for ordinal in geometry.metadata.triangles.indices {
            try Task.checkCancellation()
            let offset = ordinal * 3
            let indices = SIMD3(geometry.indices[offset], geometry.indices[offset + 1], geometry.indices[offset + 2])
            let first = geometry.vertices[Int(indices.x)]
            let second = geometry.vertices[Int(indices.y)]
            let third = geometry.vertices[Int(indices.z)]
            let hasTransparency =
                geometry.metadata.triangles[ordinal].hasMapping
                ? hasTransparentColor : (first.color.w < 1 || second.color.w < 1 || third.color.w < 1)
            if hasTransparency {
                let sum = (first.position + second.position + third.position) / 3
                transparent.append(Triangle(indices: indices, center: SIMD3(sum.x, sum.y, sum.z), ordinal: ordinal))
            } else {
                opaque.append(contentsOf: [indices.x, indices.y, indices.z])
            }
        }
        opaqueIndices = opaque
        self.transparent = transparent
    }

    /// Camera translation does not change relative depth; rotation is sufficient.
    func transparentIndices(rotation: simd_float4x4) throws -> [UInt32] {
        try Task.checkCancellation()
        guard
            [rotation.columns.0, rotation.columns.1, rotation.columns.2, rotation.columns.3]
                .allSatisfy({ column in (0..<4).allSatisfy { column[$0].isFinite } })
        else { throw BakedMetalPreparationError.invalidCamera }
        let depths = try transparent.map { triangle -> (Float, Triangle) in
            try Task.checkCancellation()
            let depth = (rotation * SIMD4(triangle.center, 1)).z
            guard depth.isFinite else { throw BakedMetalPreparationError.invalidCamera }
            return (depth, triangle)
        }
        var comparisons = 0
        let ordered = try depths.sorted { lhs, rhs in
            comparisons += 1
            if comparisons.isMultiple(of: 1024) { try Task.checkCancellation() }
            return lhs.0 == rhs.0 ? lhs.1.ordinal < rhs.1.ordinal : lhs.0 < rhs.0
        }
        var result: [UInt32] = []
        result.reserveCapacity(transparentIndexCount)
        for (_, triangle) in ordered {
            try Task.checkCancellation()
            result.append(contentsOf: [triangle.indices.x, triangle.indices.y, triangle.indices.z])
        }
        return result
    }
}
