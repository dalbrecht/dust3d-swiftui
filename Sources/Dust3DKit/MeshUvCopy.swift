import Dust3DEngine
import Foundation

struct MeshUvCounts {
    let triangles: Int
    let charts: Int
    let gradients: Int
    let components: Int
    let expandedVertices: Int
    let payload: Int

    func validate(maximumPayloadBytes: Int) throws {
        guard expandedVertices > 0, expandedVertices.isMultiple(of: 3),
            triangles == expandedVertices / 3, charts >= 0, gradients >= 0, components >= 0,
            payload > 0, payload <= maximumPayloadBytes
        else { throw MeshUvDataError.invalidBufferCounts }
        var remaining = payload
        for (count, width) in [
            (triangles, MemoryLayout<Dust3DUvTriangle>.stride),
            (charts, MemoryLayout<Dust3DUvChart>.stride),
            (gradients, MemoryLayout<Dust3DUvGradient>.stride),
        ] {
            guard count >= 0, count <= remaining / width else { throw MeshUvDataError.invalidBufferCounts }
            remaining -= count * width
        }
        guard components <= remaining else { throw MeshUvDataError.invalidBufferCounts }
    }
}

enum MeshUvCopy {
    static func componentIdentifier(_ pointer: UnsafePointer<CChar>?) throws -> String {
        do {
            return try MeshSourceCopy.identifier(pointer)
        } catch let cause as MeshSourceDataError {
            throw MeshLoadingError(
                status: 3, message: "The engine returned an invalid UV component identity: \(cause).")
        }
    }

    static func imageIdentifier(_ bytes: [UInt8]) throws -> String? {
        guard let end = bytes.firstIndex(of: 0), end <= 38 else { throw MeshUvDataError.invalidIdentity }
        if end == 0 { return nil }
        guard let identifier = String(bytes: bytes[..<end], encoding: .utf8) else {
            throw MeshUvDataError.invalidIdentity
        }
        return identifier
    }

    static func copy(_ owner: OpaquePointer, geometry: OpaquePointer, maximumPayloadBytes: Int) throws
        -> MeshUvMetadata
    {
        do {
            try Task.checkCancellation()
            let counts = MeshUvCounts(
                triangles: dust3d_uv_mesh_triangle_count(owner), charts: dust3d_uv_mesh_chart_count(owner),
                gradients: dust3d_uv_mesh_gradient_count(owner), components: dust3d_uv_mesh_component_count(owner),
                expandedVertices: dust3d_mesh_vertex_count(geometry), payload: dust3d_uv_mesh_payload_bytes(owner))
            try counts.validate(maximumPayloadBytes: maximumPayloadBytes)
            guard let triangles = dust3d_uv_mesh_triangles(owner) else { throw MeshUvDataError.invalidBufferCounts }
            let charts = dust3d_uv_mesh_charts(owner)
            let gradients = dust3d_uv_mesh_gradients(owner)
            guard counts.charts == 0 || charts != nil, counts.gradients == 0 || gradients != nil else {
                throw MeshUvDataError.invalidBufferCounts
            }
            let identifiers = try (0..<counts.components).map { index in
                try Task.checkCancellation()
                return try componentIdentifier(dust3d_uv_mesh_component_id(owner, index))
            }
            let rawTriangles = try UnsafeBufferPointer(start: triangles, count: counts.triangles).map { value in
                try Task.checkCancellation()
                return RawMeshUvTriangle(
                    corners: MeshUvCorners(
                        first: SIMD2(value.uv.0.0, value.uv.0.1), second: SIMD2(value.uv.1.0, value.uv.1.1),
                        third: SIMD2(value.uv.2.0, value.uv.2.1)), known: value.known,
                    componentKind: value.component_kind.rawValue, componentIndex: value.component_index)
            }
            let rawCharts = try UnsafeBufferPointer(start: charts, count: counts.charts).map { value in
                try Task.checkCancellation()
                var value = value
                let imageID = try withUnsafeBytes(of: &value.image_id) { try imageIdentifier(Array($0)) }
                return RawMeshUvChart(
                    origin: SIMD2(value.left, value.top), size: SIMD2(value.width, value.height),
                    color: SIMD4(value.color.0, value.color.1, value.color.2, value.color.3),
                    flipped: value.flipped, componentKind: value.component_kind.rawValue,
                    componentIndex: value.component_index, imageID: imageID)
            }
            let copiedGradients = try UnsafeBufferPointer(start: gradients, count: counts.gradients).map { value in
                try Task.checkCancellation()
                return MeshUvGradient(
                    chartIndex: value.chart_index,
                    largeColor: SIMD4(
                        value.large_color.0, value.large_color.1, value.large_color.2, value.large_color.3),
                    smallColor: SIMD4(
                        value.small_color.0, value.small_color.1, value.small_color.2, value.small_color.3),
                    resolution: value.resolution)
            }
            try Task.checkCancellation()
            return try MeshUvMetadata(
                componentIDs: identifiers, triangles: rawTriangles, charts: rawCharts, gradients: copiedGradients,
                expandedVertexCount: counts.expandedVertices, packedTextureSize: dust3d_uv_mesh_texture_size(owner))
        } catch let cause as MeshUvDataError {
            throw MeshLoadingError(status: 3, message: "The engine returned invalid UV metadata: \(cause).")
        }
    }
}
