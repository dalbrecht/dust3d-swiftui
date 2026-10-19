import Dust3DEngine
import Foundation

struct ImportedSurfaceCopyBudget {
    let maximum: Int
    private(set) var used = 0
    mutating func charge(_ count: Int, width: Int = 1) throws {
        guard count >= 0, width > 0 else { throw ImportedSurfaceError.invalidNativeCounts }
        guard count <= (maximum - used) / width else { throw ImportedSurfaceError.copyLimitExceeded }
        used += count * width
    }
}

enum ImportedSurfaceCopy {
    static func identity(_ pointer: UnsafePointer<CChar>?, budget: inout ImportedSurfaceCopyBudget) throws -> String {
        let value: String
        do { value = try MeshSourceCopy.identifier(pointer) } catch { throw ImportedSurfaceError.invalidIdentity }
        try budget.charge(value.utf8.count + 1)
        return value
    }

    static func index(_ value: Int, count: Int) throws -> Int? {
        if value == -1 { return nil }  // C SIZE_MAX imports as the size_t bit pattern -1.
        guard value >= 0, value < count else { throw ImportedSurfaceError.invalidTriangle }
        return value
    }

    static func triangle(_ value: Dust3DImportedSurfaceTriangle, models: Int, components: Int) throws
        -> ImportedSurfaceTriangle
    {
        guard value.uv_known == 0 || value.uv_known == 1 else { throw ImportedSurfaceError.invalidTriangle }
        let model = try index(value.model_index, count: models)
        let component = try index(value.component_index, count: components)
        let uv = MeshUvCorners(
            first: SIMD2(value.uv.0.0, value.uv.0.1), second: SIMD2(value.uv.1.0, value.uv.1.1),
            third: SIMD2(value.uv.2.0, value.uv.2.1))
        let coordinates = [uv.first, uv.second, uv.third]
        guard coordinates.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
            value.uv_known == 1 ? model != nil : coordinates.allSatisfy({ $0 == .zero })
        else { throw ImportedSurfaceError.invalidTriangle }
        let colors = ImportedSurfaceColors(
            first: SIMD4(value.color.0.0, value.color.0.1, value.color.0.2, value.color.0.3),
            second: SIMD4(value.color.1.0, value.color.1.1, value.color.1.2, value.color.1.3),
            third: SIMD4(value.color.2.0, value.color.2.1, value.color.2.2, value.color.2.3))
        guard
            [colors.first, colors.second, colors.third].allSatisfy({ color in
                (0..<4).allSatisfy { color[$0].isFinite && (0...1).contains(color[$0]) }
            })
        else { throw ImportedSurfaceError.invalidTriangle }
        let encoding: ImportedSurfaceColorEncoding
        switch value.color_encoding {
        case DUST3D_SURFACE_COLOR_SRGB: encoding = .sRGB
        case DUST3D_SURFACE_COLOR_LINEAR: encoding = .linear
        default: throw ImportedSurfaceError.invalidTriangle
        }
        return ImportedSurfaceTriangle(
            sourceUVs: value.uv_known == 1 ? uv : nil, colors: colors, colorEncoding: encoding, modelIndex: model,
            componentIndex: component)
    }

    static func validateCounts(triangles: Int, vertices: Int, models: Int, components: Int, payload: Int, maximum: Int)
        throws
    {
        guard vertices > 0, vertices.isMultiple(of: 3), triangles == vertices / 3,
            models >= 0, components >= 0, payload > 0, payload <= maximum
        else { throw ImportedSurfaceError.invalidNativeCounts }
        var remaining = payload
        for (count, width) in [
            (vertices, MemoryLayout<Dust3DVertex>.stride),
            (triangles, MemoryLayout<Dust3DImportedSurfaceTriangle>.stride),
            (models, MemoryLayout<UnsafePointer<CChar>>.stride),
            (components, MemoryLayout<UnsafePointer<CChar>>.stride),
        ] {
            guard count >= 0, count <= remaining / width else { throw ImportedSurfaceError.invalidNativeCounts }
            remaining -= count * width
        }
    }

    static func component(_ owner: OpaquePointer, index: Int, budget: inout ImportedSurfaceCopyBudget) throws
        -> ImportedSurfaceComponent
    {
        let id = try identity(dust3d_imported_surface_mesh_component_id(owner, index), budget: &budget)
        let kind: ImportedSurfaceComponentKind
        switch dust3d_imported_surface_mesh_component_kind(owner, index) {
        case DUST3D_SURFACE_COMPONENT_ORIGINAL: kind = .original
        case DUST3D_SURFACE_COMPONENT_GENERATED: kind = .generated
        default: throw ImportedSurfaceError.invalidComponent
        }
        return ImportedSurfaceComponent(id: id, kind: kind)
    }

    static func copy(
        _ owner: OpaquePointer, options: ImportedSurfaceOptions,
        copyGeometry: (OpaquePointer) throws -> Mesh = MeshLoader.copyNativeMesh
    ) throws -> ImportedSurfaceMesh {
        try Task.checkCancellation()
        guard let geometry = dust3d_imported_surface_mesh_geometry(owner),
            let source = dust3d_imported_surface_mesh_triangles(owner)
        else { throw ImportedSurfaceError.invalidNativeCounts }
        let triangles = dust3d_imported_surface_mesh_triangle_count(owner)
        let vertices = dust3d_mesh_vertex_count(geometry)
        let models = dust3d_imported_surface_mesh_model_count(owner)
        let components = dust3d_imported_surface_mesh_component_count(owner)
        let payload = dust3d_imported_surface_mesh_payload_bytes(owner)
        try validateCounts(
            triangles: triangles, vertices: vertices, models: models, components: components, payload: payload,
            maximum: options.maximumNativePayloadBytes == 0
                ? Int(DUST3D_DEFAULT_IMPORTED_SURFACE_PAYLOAD_BYTES) : options.maximumNativePayloadBytes)
        var budget = ImportedSurfaceCopyBudget(maximum: options.maximumCopiedPayloadBytes)
        try budget.charge(1, width: MemoryLayout<ImportedSurfaceMesh>.stride)
        try budget.charge(vertices, width: MemoryLayout<MeshVertex>.stride)
        try budget.charge(triangles, width: MemoryLayout<ImportedSurfaceTriangle>.stride)
        try budget.charge(models, width: MemoryLayout<ImportedSurfaceModelIdentity>.stride)
        try budget.charge(components, width: MemoryLayout<ImportedSurfaceComponent>.stride)
        var modelIDs: [ImportedSurfaceModelIdentity] = []
        modelIDs.reserveCapacity(models)
        try budget.charge(modelIDs.capacity - models, width: MemoryLayout<ImportedSurfaceModelIdentity>.stride)
        var modelKeys: Set<[UInt8]> = []
        for index in 0..<models {
            try Task.checkCancellation()
            let id = try identity(dust3d_imported_surface_mesh_model_id(owner, index), budget: &budget)
            guard modelKeys.insert(Array(id.utf8)).inserted else { throw ImportedSurfaceError.invalidIdentity }
            modelIDs.append(try ImportedSurfaceModelIdentity(id: id))
        }
        var catalog: [ImportedSurfaceComponent] = []
        catalog.reserveCapacity(components)
        try budget.charge(catalog.capacity - components, width: MemoryLayout<ImportedSurfaceComponent>.stride)
        var componentKeys: Set<[UInt8]> = []
        for index in 0..<components {
            try Task.checkCancellation()
            let entry = try component(owner, index: index, budget: &budget)
            guard componentKeys.insert(Array(entry.id.utf8)).inserted else {
                throw ImportedSurfaceError.invalidIdentity
            }
            catalog.append(entry)
        }
        var records: [ImportedSurfaceTriangle] = []
        records.reserveCapacity(triangles)
        try budget.charge(records.capacity - triangles, width: MemoryLayout<ImportedSurfaceTriangle>.stride)
        for index in 0..<triangles {
            try Task.checkCancellation()
            records.append(try triangle(source[index], models: models, components: components))
        }
        try Task.checkCancellation()
        let mesh = try copyGeometry(geometry)
        try budget.charge(mesh.vertices.capacity - vertices, width: MemoryLayout<MeshVertex>.stride)
        try budget.charge(mesh.warning.utf8.count + 1)
        try Task.checkCancellation()
        return ImportedSurfaceMesh(
            mesh: mesh, triangles: records, modelIDs: modelIDs, components: catalog, nativePayloadBytes: payload,
            copiedPayloadBytes: budget.used)
    }
}
