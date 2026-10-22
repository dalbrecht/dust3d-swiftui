import Dust3DEngine
import Foundation

struct SourceBakeCopyBudget {
    let maximum: Int
    private(set) var used = 0

    mutating func charge(_ count: Int, width: Int = 1) throws {
        guard count >= 0, width > 0 else { throw SourceMeshBakeError.invalidNativeCounts }
        guard count <= (maximum - used) / width else { throw SourceMeshBakeError.copyLimitExceeded }
        used += count * width
    }
}

enum SourceBakedCopy {
    static func index(_ value: Int, count: Int) throws -> Int? {
        if value == -1 { return nil }
        guard value >= 0, value < count else { throw SourceMeshBakeError.invalidTriangle }
        return value
    }

    static func triangle(_ value: Dust3DSourceBakedTriangle, models: Int, components: Int) throws -> SourceBakedTriangle
    {
        guard value.uv_known <= 1, value.policy_known <= 1, value.is_double_sided <= 1 else {
            throw SourceMeshBakeError.invalidTriangle
        }
        let uv = MeshUvCorners(
            first: SIMD2(value.uv.0.0, value.uv.0.1), second: SIMD2(value.uv.1.0, value.uv.1.1),
            third: SIMD2(value.uv.2.0, value.uv.2.1))
        let coordinates = [uv.first, uv.second, uv.third]
        guard
            coordinates.allSatisfy({ point in (0..<2).allSatisfy { point[$0].isFinite && (0...1).contains(point[$0]) } }
            ),
            value.uv_known == 1 || coordinates.allSatisfy({ $0 == .zero })
        else { throw SourceMeshBakeError.invalidTriangle }
        let tangent = try MeshBakedCopy.tangent(value.tangent)
        guard !tangent.hasMapping || value.uv_known == 1 else { throw SourceMeshBakeError.invalidTriangle }
        let policy: SourceBakedPolicy?
        if value.policy_known == 1 {
            let mode: ImportedAlphaMode
            switch value.alpha_mode {
            case DUST3D_IMPORTED_ALPHA_OPAQUE: mode = .opaque
            case DUST3D_IMPORTED_ALPHA_MASK: mode = .mask
            case DUST3D_IMPORTED_ALPHA_BLEND: mode = .blend
            default: throw SourceMeshBakeError.invalidPolicy
            }
            guard value.alpha_cutoff.isFinite, value.alpha_cutoff >= 0 else {
                throw SourceMeshBakeError.invalidPolicy
            }
            policy = SourceBakedPolicy(
                alphaMode: mode, alphaCutoff: value.alpha_cutoff, isDoubleSided: value.is_double_sided == 1)
        } else {
            policy = nil
        }
        return try SourceBakedTriangle(
            packedUVs: value.uv_known == 1 ? uv : nil, tangent: tangent, policy: policy,
            modelIndex: index(value.model_index, count: models),
            componentIndex: index(value.component_index, count: components))
    }

    static func identity(_ pointer: UnsafePointer<CChar>?, budget: inout SourceBakeCopyBudget) throws
        -> ImportedSurfaceIdentity
    {
        let key: ImportedSurfaceIdentity
        do { key = try ImportedSurfaceIdentity(rawValue: MeshSourceCopy.identifier(pointer)) } catch {
            throw SourceMeshBakeError.invalidCatalog
        }
        try budget.charge(key.rawValue.utf8.count + 1)
        return key
    }

    @discardableResult
    static func validateCounts(vertices: Int, triangles: Int, models: Int, components: Int, payload: Int, maximum: Int)
        throws -> Int
    {
        guard vertices > 0, vertices.isMultiple(of: 3), triangles == vertices / 3,
            models >= 0, components >= 0, payload > 0, payload <= maximum
        else { throw SourceMeshBakeError.invalidNativeCounts }
        var remaining = payload
        for (count, width) in [
            (vertices, MemoryLayout<Dust3DVertex>.stride),
            (triangles, MemoryLayout<Dust3DSourceBakedTriangle>.stride),
            (models, MemoryLayout<UnsafePointer<CChar>>.stride),
            (components, MemoryLayout<UnsafePointer<CChar>>.stride),
        ] {
            guard count <= remaining / width else { throw SourceMeshBakeError.invalidNativeCounts }
            remaining -= count * width
        }
        return remaining
    }

    static func samplingLod(_ value: Double, maps: MeshTextureMaps) throws -> Double {
        let images = [maps.color, maps.normal, maps.metallic, maps.roughness, maps.emissive].compactMap { $0 }
        let minimumDimension = images.reduce(8192) { min($0, min($1.width, $1.height)) }
        guard minimumDimension > 0, value.isFinite, value >= 0,
            value <= Double(Int.bitWidth - minimumDimension.leadingZeroBitCount - 1)
        else { throw SourceMeshBakeError.invalidSamplingLod }
        return value
    }

    static func image(
        _ owner: OpaquePointer, map: Dust3DTextureMap, required: Bool,
        nativeRemaining: inout Int, budget: inout SourceBakeCopyBudget
    ) throws -> MeshTextureImage? {
        let view = dust3d_source_baked_mesh_texture(owner, map.rawValue)
        try budget.charge(view.byte_count)
        return try MeshBakedCopy.image(view, required: required, remaining: &nativeRemaining)
    }

    static func copy(_ owner: OpaquePointer, options: SourceMeshBakeOptions) throws -> SourceBakedMesh {
        guard let geometry = dust3d_source_baked_mesh_geometry(owner),
            let source = dust3d_source_baked_mesh_triangles(owner)
        else { throw SourceMeshBakeError.invalidNativeCounts }
        let vertices = dust3d_mesh_vertex_count(geometry)
        let triangles = dust3d_source_baked_mesh_triangle_count(owner)
        let models = dust3d_source_baked_mesh_model_count(owner)
        let components = dust3d_source_baked_mesh_component_count(owner)
        let payload = dust3d_source_baked_mesh_payload_bytes(owner)
        var remaining = try validateCounts(
            vertices: vertices, triangles: triangles, models: models, components: components, payload: payload,
            maximum: options.maximumNativePayloadBytes == 0 ? 256 * 1024 * 1024 : options.maximumNativePayloadBytes)
        var budget = SourceBakeCopyBudget(maximum: options.maximumCopiedPayloadBytes)
        try budget.charge(1, width: MemoryLayout<SourceBakedMesh>.stride)
        try budget.charge(vertices, width: MemoryLayout<MeshVertex>.stride)
        try budget.charge(triangles, width: MemoryLayout<SourceBakedTriangle>.stride)
        try budget.charge(models, width: MemoryLayout<ImportedSurfaceIdentity>.stride)
        try budget.charge(components, width: MemoryLayout<ImportedSurfaceComponent>.stride)
        var modelIDs: [ImportedSurfaceIdentity] = []
        modelIDs.reserveCapacity(models)
        try budget.charge(modelIDs.capacity - models, width: MemoryLayout<ImportedSurfaceIdentity>.stride)
        var modelKeys: Set<ImportedSurfaceIdentity> = []
        for index in 0..<models {
            try Task.checkCancellation()
            let key = try identity(dust3d_source_baked_mesh_model_id(owner, index), budget: &budget)
            guard modelKeys.insert(key).inserted else { throw SourceMeshBakeError.invalidCatalog }
            modelIDs.append(key)
        }
        var catalog: [ImportedSurfaceComponent] = []
        catalog.reserveCapacity(components)
        try budget.charge(catalog.capacity - components, width: MemoryLayout<ImportedSurfaceComponent>.stride)
        var componentKeys: Set<ImportedSurfaceIdentity> = []
        for index in 0..<components {
            try Task.checkCancellation()
            let key = try identity(dust3d_source_baked_mesh_component_id(owner, index), budget: &budget)
            guard componentKeys.insert(key).inserted else { throw SourceMeshBakeError.invalidCatalog }
            let kind: ImportedSurfaceComponentKind
            switch dust3d_source_baked_mesh_component_kind(owner, index) {
            case DUST3D_SURFACE_COMPONENT_ORIGINAL: kind = .original
            case DUST3D_SURFACE_COMPONENT_GENERATED: kind = .generated
            default: throw SourceMeshBakeError.invalidCatalog
            }
            catalog.append(ImportedSurfaceComponent(id: key, kind: kind))
        }
        var records: [SourceBakedTriangle] = []
        records.reserveCapacity(triangles)
        try budget.charge(records.capacity - triangles, width: MemoryLayout<SourceBakedTriangle>.stride)
        for index in 0..<triangles {
            try Task.checkCancellation()
            records.append(try triangle(source[index], models: models, components: components))
        }
        guard
            let color = try image(
                owner, map: DUST3D_TEXTURE_COLOR, required: true, nativeRemaining: &remaining, budget: &budget)
        else {
            throw SourceMeshBakeError.invalidNativeCounts
        }
        let maps = try MeshTextureMaps(
            color: color,
            normal: image(
                owner, map: DUST3D_TEXTURE_NORMAL, required: false, nativeRemaining: &remaining, budget: &budget),
            metallic: image(
                owner, map: DUST3D_TEXTURE_METALLIC, required: true, nativeRemaining: &remaining, budget: &budget),
            roughness: image(
                owner, map: DUST3D_TEXTURE_ROUGHNESS, required: true, nativeRemaining: &remaining, budget: &budget),
            emissive: image(
                owner, map: DUST3D_TEXTURE_EMISSIVE, required: true, nativeRemaining: &remaining, budget: &budget))
        let lod = try samplingLod(dust3d_source_baked_mesh_maximum_sampling_lod(owner), maps: maps)
        try Task.checkCancellation()
        let mesh = try MeshLoader.copyNativeMesh(geometry)
        try budget.charge(mesh.vertices.capacity - vertices, width: MemoryLayout<MeshVertex>.stride)
        try budget.charge(mesh.warning.utf8.count + 1)
        try Task.checkCancellation()
        return SourceBakedMesh(
            geometry: mesh, triangles: records, modelIDs: modelIDs, components: catalog, textures: maps,
            maximumSamplingLod: lod, nativePayloadBytes: payload, copiedPayloadBytes: budget.used)
    }
}
