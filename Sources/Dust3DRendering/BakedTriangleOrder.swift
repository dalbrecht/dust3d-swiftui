import Dust3DKit
import simd

struct BakedDrawBatch: Sendable {
    let policy: SourceBakedPolicy?
    let indexOffset: Int
    var indexCount: Int
}

struct BakedDrawIndices: Sendable {
    let indices: [UInt32]
    let batches: [BakedDrawBatch]
}

/// Opaque indices retain source order. Transparent triangles sort in view space;
/// intersecting/coplanar transparent surfaces remain a documented sorting limit.
struct BakedTriangleOrder: Sendable {
    private struct Triangle: Sendable {
        let indices: SIMD3<UInt32>
        let center: SIMD3<Float>
        let ordinal: Int
        let policy: SourceBakedPolicy?
    }

    let opaqueIndices: [UInt32]
    let opaqueBatches: [BakedDrawBatch]
    private let transparent: [Triangle]
    var transparentIndexCount: Int { transparent.count * 3 }

    init(geometry: TexturedRenderGeometry, hasTransparentColor: Bool) throws {
        var opaque: [Triangle] = []
        var transparent: [Triangle] = []
        for ordinal in 0..<geometry.metadata.triangleCount {
            try Task.checkCancellation()
            let offset = ordinal * 3
            let indices = SIMD3(geometry.indices[offset], geometry.indices[offset + 1], geometry.indices[offset + 2])
            let first = geometry.vertices[Int(indices.x)]
            let second = geometry.vertices[Int(indices.y)]
            let third = geometry.vertices[Int(indices.z)]
            let observedTransparency =
                geometry.metadata.hasMapping(at: ordinal)
                ? hasTransparentColor : (first.color.w < 1 || second.color.w < 1 || third.color.w < 1)
            let policy = geometry.metadata.policy(at: ordinal)
            let hasTransparency = policy.map { $0.alphaMode == .blend } ?? observedTransparency
            let sum = (first.position + second.position + third.position) / 3
            let triangle = Triangle(
                indices: indices, center: SIMD3(sum.x, sum.y, sum.z), ordinal: ordinal, policy: policy)
            if hasTransparency {
                transparent.append(triangle)
            } else {
                opaque.append(triangle)
            }
        }
        let draws = try Self.draws(opaque)
        opaqueIndices = draws.indices
        opaqueBatches = draws.batches
        self.transparent = transparent
    }

    /// Camera translation does not change relative depth; rotation is sufficient.
    func transparentIndices(rotation: simd_float4x4) throws -> [UInt32] {
        try transparentDraws(rotation: rotation).indices
    }

    func transparentDraws(rotation: simd_float4x4) throws -> BakedDrawIndices {
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
        return try Self.draws(ordered.map(\.1))
    }

    private static func draws(_ triangles: [Triangle]) throws -> BakedDrawIndices {
        var indices: [UInt32] = []
        var batches: [BakedDrawBatch] = []
        indices.reserveCapacity(triangles.count * 3)
        for triangle in triangles {
            try Task.checkCancellation()
            if let last = batches.last, last.policy == triangle.policy {
                batches[batches.count - 1].indexCount += 3
            } else {
                guard batches.count < 4096 else { throw BakedMetalPreparationError.drawLimitExceeded }
                batches.append(BakedDrawBatch(policy: triangle.policy, indexOffset: indices.count, indexCount: 3))
            }
            indices.append(contentsOf: [triangle.indices.x, triangle.indices.y, triangle.indices.z])
        }
        return BakedDrawIndices(indices: indices, batches: batches)
    }
}
