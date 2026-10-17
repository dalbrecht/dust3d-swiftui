import Dust3DEngine
import Foundation

/// Validate logical byte accounting before constructing any borrowed-buffer copy.
enum MeshBakedCopy {
    static func image(_ view: Dust3DTextureView, required: Bool, remaining: inout Int) throws -> MeshTextureImage? {
        if view.pixels == nil {
            guard !required, view.width == 0, view.height == 0, view.row_stride == 0, view.byte_count == 0 else {
                throw MeshLoadingError(status: 3, message: "The engine returned an incomplete baked image view.")
            }
            return nil
        }
        guard (1...8192).contains(view.width), (1...8192).contains(view.height),
            view.row_stride == view.width * 4, view.byte_count == view.row_stride * view.height,
            view.byte_count <= remaining, let pixels = view.pixels
        else {
            throw MeshLoadingError(status: 3, message: "The engine returned invalid baked image dimensions or payload.")
        }
        remaining -= view.byte_count
        return MeshTextureImage(
            width: view.width, height: view.height, rowStride: view.row_stride,
            pixels: Data(bytes: pixels, count: view.byte_count))
    }

    static func tangent(_ value: Dust3DTextureTangent) throws -> MeshTextureTangent {
        let direction = SIMD3(value.direction.0, value.direction.1, value.direction.2)
        let lengthSquared = direction.x * direction.x + direction.y * direction.y + direction.z * direction.z
        guard value.known == 0 || value.known == 1,
            direction.x.isFinite, direction.y.isFinite, direction.z.isFinite,
            value.handedness == 1 || value.handedness == -1,
            value.known == 0 || abs(lengthSquared - 1) < 0.0001
        else { throw MeshLoadingError(status: 3, message: "The engine returned an invalid baked tangent frame.") }
        return MeshTextureTangent(direction: direction, handedness: value.handedness, hasMapping: value.known == 1)
    }

    static func copy(_ owner: OpaquePointer, options: MeshBakeOptions) throws -> MeshWithBakedTextures {
        guard let uvs = dust3d_baked_mesh_uvs(owner), let nativeGeometry = dust3d_uv_mesh_geometry(uvs) else {
            throw MeshLoadingError(status: 3, message: "The engine returned no baked geometry owner.")
        }
        let effectiveQuota = options.maximumBakePayloadBytes == 0 ? 256 * 1024 * 1024 : options.maximumBakePayloadBytes
        let metadataQuota =
            options.maximumMetadataPayloadBytes == 0 ? 64 * 1024 * 1024 : options.maximumMetadataPayloadBytes
        let count = dust3d_baked_mesh_tangent_count(owner)
        var remaining = dust3d_baked_mesh_payload_bytes(owner)
        guard remaining > 0, remaining <= effectiveQuota, count > 0,
            count == dust3d_uv_mesh_triangle_count(uvs), count <= remaining / MemoryLayout<Dust3DTextureTangent>.stride,
            let source = dust3d_baked_mesh_tangents(owner)
        else {
            throw MeshLoadingError(
                status: 3, message: "The engine returned inconsistent baked tangent counts or payload.")
        }
        remaining -= count * MemoryLayout<Dust3DTextureTangent>.stride
        let tangents = try UnsafeBufferPointer(start: source, count: count).map {
            try Task.checkCancellation()
            return try tangent($0)
        }
        guard
            let color = try image(
                dust3d_baked_mesh_texture(owner, DUST3D_TEXTURE_COLOR.rawValue), required: true, remaining: &remaining)
        else {
            throw MeshLoadingError(status: 3, message: "The engine returned no mandatory baked color map.")
        }
        let maps = try MeshTextureMaps(
            color: color,
            normal: image(
                dust3d_baked_mesh_texture(owner, DUST3D_TEXTURE_NORMAL.rawValue), required: false, remaining: &remaining
            ),
            metallic: image(
                dust3d_baked_mesh_texture(owner, DUST3D_TEXTURE_METALLIC.rawValue), required: false,
                remaining: &remaining),
            roughness: image(
                dust3d_baked_mesh_texture(owner, DUST3D_TEXTURE_ROUGHNESS.rawValue), required: false,
                remaining: &remaining),
            emissive: image(
                dust3d_baked_mesh_texture(owner, DUST3D_TEXTURE_EMISSIVE.rawValue), required: false,
                remaining: &remaining))
        guard remaining == 0 else {
            throw MeshLoadingError(status: 3, message: "The engine returned unexplained baked payload bytes.")
        }
        let metadata = try MeshUvCopy.copy(uvs, geometry: nativeGeometry, maximumPayloadBytes: metadataQuota)
        let geometry = try MeshLoader.copyNativeMesh(nativeGeometry)
        try Task.checkCancellation()
        return MeshWithBakedTextures(geometry: geometry, metadata: metadata, tangents: tangents, textures: maps)
    }
}
