import Dust3DKit
import simd

/// Pointer coordinates and viewport size use the same bottom-left view-point units.
/// The transform is the renderer's normalized-model-to-Metal-clip matrix.
public struct MeshPickInput: Sendable {
    /// Pointer location in bottom-left-origin view-point units, independent of backing scale.
    public let point: SIMD2<Float>
    /// Viewport width and height in the same view-point units as point.
    public let size: SIMD2<Float>
    /// Full-stream normalized-model-to-Metal-clip transform; clip depth is zero to one.
    public let transform: simd_float4x4

    /// Capture immutable pointer and camera input for background triangle picking.
    /// - Parameters:
    ///   - point: Bottom-left-origin pointer location in view-point units.
    ///   - size: Viewport dimensions in those same units; do not use backing pixels.
    ///   - transform: The renderer's full-stream normalization-to-clip camera matrix.
    public init(point: SIMD2<Float>, size: SIMD2<Float>, transform: simd_float4x4) {
        self.point = point
        self.size = size
        self.transform = transform
    }
}

/// Body hits occlude bone selection. Bone indices retain original source order.
package enum MeshPickResult: Sendable, Equatable {
    case miss
    case body
    case bone(Int)
}

/// Immutable copied triangles and the full-stream frame, without a normalized copy.
/// Preparation and picking belong on a worker; neither performs GPU or native work.
package struct MeshPickingGeometry: Sendable {
    private let mesh: Mesh
    private let skeletonTriangleOwners: [UInt32]
    private let bounds: RenderBounds

    package var hasBones: Bool { !skeletonTriangleOwners.isEmpty }

    package init(mesh: Mesh, skeletonTriangleOwners: [UInt32], jointCount: Int) throws {
        try Task.checkCancellation()
        guard !mesh.vertices.isEmpty, mesh.vertices.count.isMultiple(of: 3),
            (0...256).contains(jointCount), skeletonTriangleOwners.count <= mesh.triangleCount
        else { throw Self.invalid("triangle or joint correspondence") }
        for (index, vertex) in mesh.vertices.enumerated() {
            if index.isMultiple(of: 1024) { try Task.checkCancellation() }
            guard (0..<3).allSatisfy({ vertex.position[$0].isFinite }) else {
                throw Self.invalid("nonfinite triangle position")
            }
        }
        for (index, owner) in skeletonTriangleOwners.enumerated() {
            if index.isMultiple(of: 1024) { try Task.checkCancellation() }
            guard owner < UInt32(jointCount) else { throw Self.invalid("source joint index") }
        }
        bounds = try RenderBounds(vertices: mesh.vertices, cancellationCheck: { try Task.checkCancellation() })
        self.mesh = mesh
        self.skeletonTriangleOwners = skeletonTriangleOwners
        try Task.checkCancellation()
    }

    /// Pick the nearest two-sided triangle inside the visible near/far clip segment.
    /// The span addresses full-buffer vertices and never changes normalization.
    /// Source-order ties are stable. Invalid pointer/transform input returns miss;
    /// malformed spans and cooperative cancellation throw without publishing a hit.
    package func pick(_ input: MeshPickInput, drawRange: Range<Int>?) throws -> MeshPickResult {
        try Task.checkCancellation()
        let span = try MeshDrawRange(vertexCount: mesh.vertices.count, range: drawRange)
        guard span.vertexCount > 0, let ray = ray(input) else { return .miss }
        var nearest = Double.infinity
        var result = MeshPickResult.miss
        let end = span.vertexStart + span.vertexCount
        for vertexIndex in stride(from: span.vertexStart, to: end, by: 3) {
            if ((vertexIndex - span.vertexStart) / 3).isMultiple(of: 1024) { try Task.checkCancellation() }
            let a = Self.double(mesh.vertices[vertexIndex].position)
            let b = Self.double(mesh.vertices[vertexIndex + 1].position)
            let c = Self.double(mesh.vertices[vertexIndex + 2].position)
            if let distance = Self.intersection(ray: ray, a: a, b: b, c: c), distance < nearest {
                nearest = distance
                let triangle = vertexIndex / 3
                result = triangle < skeletonTriangleOwners.count ? .bone(Int(skeletonTriangleOwners[triangle])) : .body
            }
        }
        try Task.checkCancellation()
        return result
    }

    private struct Ray {
        let origin: SIMD3<Double>
        let direction: SIMD3<Double>
    }

    private func ray(_ input: MeshPickInput) -> Ray? {
        guard (0..<2).allSatisfy({ input.point[$0].isFinite && input.size[$0].isFinite && input.size[$0] > 0 }),
            input.point.x >= 0, input.point.y >= 0,
            input.point.x <= input.size.x, input.point.y <= input.size.y
        else { return nil }
        let source = input.transform
        guard
            [source.columns.0, source.columns.1, source.columns.2, source.columns.3].allSatisfy({ column in
                (0..<4).allSatisfy { column[$0].isFinite }
            })
        else { return nil }
        let matrix = simd_double4x4(
            columns: (
                Self.double(source.columns.0), Self.double(source.columns.1),
                Self.double(source.columns.2), Self.double(source.columns.3)
            ))
        let inverse = matrix.inverse
        guard
            [inverse.columns.0, inverse.columns.1, inverse.columns.2, inverse.columns.3].allSatisfy({ column in
                (0..<4).allSatisfy { column[$0].isFinite }
            })
        else { return nil }
        let x = Double(input.point.x) / Double(input.size.x) * 2 - 1
        let y = Double(input.point.y) / Double(input.size.y) * 2 - 1
        let near = inverse * SIMD4(x, y, 0, 1)
        let far = inverse * SIMD4(x, y, 1, 1)
        // Positive homogeneous W is required by the renderer's clip volume.
        guard near.w.isFinite, far.w.isFinite, near.w > 0, far.w > 0 else { return nil }
        let center = Self.double(bounds.center)
        let radius = Double(bounds.radius)
        let origin = SIMD3(near.x, near.y, near.z) / near.w * radius + center
        let target = SIMD3(far.x, far.y, far.z) / far.w * radius + center
        let direction = target - origin
        guard (0..<3).allSatisfy({ origin[$0].isFinite && direction[$0].isFinite }), direction != .zero else {
            return nil
        }
        return Ray(origin: origin, direction: direction)
    }

    private static func intersection(ray: Ray, a: SIMD3<Double>, b: SIMD3<Double>, c: SIMD3<Double>) -> Double? {
        let edge = b - a
        let otherEdge = c - a
        let perpendicular = simd_cross(ray.direction, otherEdge)
        let determinant = simd_dot(edge, perpendicular)
        let scale =
            max(abs(edge.x), max(abs(edge.y), abs(edge.z)))
            * max(abs(perpendicular.x), max(abs(perpendicular.y), abs(perpendicular.z)))
        // A relative error bound keeps tiny valid triangles while rejecting
        // degenerate and numerically parallel rays, independent of winding.
        guard determinant.isFinite, scale.isFinite,
            abs(determinant) > 16 * Double.ulpOfOne * scale
        else { return nil }
        let offset = ray.origin - a
        let u = simd_dot(offset, perpendicular) / determinant
        guard u.isFinite, u >= 0, u <= 1 else { return nil }
        let crossed = simd_cross(offset, edge)
        let v = simd_dot(ray.direction, crossed) / determinant
        guard v.isFinite, v >= 0, u + v <= 1 else { return nil }
        let distance = simd_dot(otherEdge, crossed) / determinant
        guard distance.isFinite, distance >= 0, distance <= 1 else { return nil }
        return distance
    }

    private static func double(_ value: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3(Double(value.x), Double(value.y), Double(value.z))
    }

    private static func double(_ value: SIMD4<Float>) -> SIMD4<Double> {
        SIMD4(Double(value.x), Double(value.y), Double(value.z), Double(value.w))
    }

    private static func invalid(_ detail: String) -> RendererError {
        .unavailable("Invalid mesh picking geometry: \(detail).")
    }
}
