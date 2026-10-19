import simd

struct ImportedDrawBatch: Sendable {
    let materialIndex: Int
    let indexOffset: Int
    var indexCount: Int
}
struct ImportedDrawIndices: Sendable {
    let indices: [UInt32]
    let batches: [ImportedDrawBatch]
}

/// Sort blended surfaces globally before coalescing adjacent model bindings.
/// Centroid sorting retains the existing intersecting/coplanar transparency limitation.
struct ImportedTriangleOrder: Sendable {
    let opaque: ImportedDrawIndices
    private let transparentTriangles: [ImportedRenderGeometry.Triangle]
    var transparentIndexCount: Int { transparentTriangles.count * 3 }

    init(geometry: ImportedRenderGeometry) throws {
        var opaque: [ImportedRenderGeometry.Triangle] = []
        var transparent: [ImportedRenderGeometry.Triangle] = []
        for triangle in geometry.triangles {
            try Task.checkCancellation()
            if triangle.isTransparent { transparent.append(triangle) } else { opaque.append(triangle) }
        }
        self.opaque = try Self.draws(opaque)
        transparentTriangles = transparent
    }

    func transparent(rotation: simd_float4x4) throws -> ImportedDrawIndices {
        try Task.checkCancellation()
        guard
            [rotation.columns.0, rotation.columns.1, rotation.columns.2, rotation.columns.3].allSatisfy({ column in
                (0..<4).allSatisfy { column[$0].isFinite }
            })
        else { throw ImportedRenderError.invalidCamera }
        let depths = try transparentTriangles.map { triangle -> (Float, ImportedRenderGeometry.Triangle) in
            try Task.checkCancellation()
            let depth = (rotation * SIMD4(triangle.center, 1)).z
            guard depth.isFinite else { throw ImportedRenderError.invalidCamera }
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

    private static func draws(_ triangles: [ImportedRenderGeometry.Triangle]) throws -> ImportedDrawIndices {
        var indices: [UInt32] = []
        var batches: [ImportedDrawBatch] = []
        indices.reserveCapacity(triangles.count * 3)
        for triangle in triangles {
            try Task.checkCancellation()
            if let last = batches.last, last.materialIndex == triangle.materialIndex {
                batches[batches.count - 1].indexCount += 3
            } else {
                guard batches.count < ImportedRenderAdmission.maximumDrawBatches else {
                    throw ImportedRenderError.bindingLimit
                }
                batches.append(
                    ImportedDrawBatch(materialIndex: triangle.materialIndex, indexOffset: indices.count, indexCount: 3))
            }
            indices.append(triangle.firstVertex)
            indices.append(triangle.firstVertex + 1)
            indices.append(triangle.firstVertex + 2)
        }
        return ImportedDrawIndices(indices: indices, batches: batches)
    }
}
