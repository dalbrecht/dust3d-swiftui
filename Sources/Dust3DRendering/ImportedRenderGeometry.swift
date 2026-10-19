import Dust3DKit
import Foundation
import simd

enum ImportedRenderError: LocalizedError, Equatable {
    case invalidLimits, invalidGeometry, invalidMaterial, invalidImage, invalidCamera, payloadLimit, bufferLimit,
        bindingLimit
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidLimits: return "The imported renderer limits are invalid."
        case .invalidGeometry: return "The imported surface has invalid or unaligned geometry, colors or UVs."
        case .invalidMaterial: return "The imported surface and material catalog do not match."
        case .invalidImage: return "An imported texture has invalid identity, dimensions or pixel storage."
        case .invalidCamera: return "The imported preview camera contains invalid values."
        case .payloadLimit: return "The imported preview exceeds its combined upload payload limit."
        case .bindingLimit: return "The imported preview exceeds 4096 material bindings or draw runs per pass."
        case .bufferLimit: return "The imported mesh exceeds this Metal device's buffer size limit."
        case .unavailable(let cause): return cause
        }
    }
}

/// Pixel quotas do not account for driver object overhead or UI-thread draw submission.
enum ImportedRenderAdmission {
    static let maximumMaterials = 4096
    static let maximumDrawBatches = 4096
}

struct ImportedRenderBudget {
    let maximum: Int
    private(set) var used = 0
    mutating func charge(_ count: Int, width: Int = 1) throws {
        guard count >= 0, width > 0, count <= (maximum - used) / width else { throw ImportedRenderError.payloadLimit }
        used += count * width
    }
}

/// Source RGBA8 rows; logical GPU pixel bytes include the requested complete mip chain.
struct ImportedRenderImage: Sendable {
    let width: Int
    let height: Int
    let rowStride: Int
    let pixels: Data
    let mipmapLevelCount: Int
    let payloadBytes: Int

    init(source: ImportedDecodedImage, id: ImportedSurfaceIdentity, mipmapped: Bool) throws {
        guard source.modelID.utf8.elementsEqual(id.rawValue.utf8),
            (1...8192).contains(source.width), (1...8192).contains(source.height),
            source.rowStride >= source.width * 4, source.rowStride <= 256 * 1024 * 1024,
            source.rowStride.isMultiple(of: 4)
        else { throw ImportedRenderError.invalidImage }
        let preceding = source.rowStride.multipliedReportingOverflow(by: source.height - 1)
        let span = preceding.partialValue.addingReportingOverflow(source.width * 4)
        guard !preceding.overflow, !span.overflow, span.partialValue <= source.pixels.count else {
            throw ImportedRenderError.invalidImage
        }
        width = source.width
        height = source.height
        rowStride = source.rowStride
        pixels = source.pixels
        var width = source.width
        var height = source.height
        var levels = 0
        var bytes = 0
        repeat {
            // Dimensions are bounded to 8192; the full RGBA mip chain fits Int on supported macOS.
            bytes += width * height * 4
            levels += 1
            if !mipmapped || (width == 1 && height == 1) { break }
            width = max(1, width / 2)
            height = max(1, height / 2)
        } while true
        mipmapLevelCount = levels
        payloadBytes = bytes
    }
}

struct ImportedMaterialUniforms: Sendable {
    let baseColor: SIMD4<Float>
    let emissiveMetallic: SIMD4<Float>
    /// Roughness, alpha cutoff, alpha mode (opaque/mask/blend), texture enabled.
    let parameters: SIMD4<Float>
}

struct ImportedRenderMaterialPlan: Sendable {
    let uniforms: ImportedMaterialUniforms
    let alphaMode: ImportedAlphaMode
    let isDoubleSided: Bool
    let sampler: ImportedSamplerPlan
    let image: ImportedRenderImage?

    init(source: ImportedRenderMaterial, id: ImportedSurfaceIdentity) throws {
        let value = source.definition
        guard source.id == id, value.id.utf8.elementsEqual(id.rawValue.utf8),
            (0..<4).allSatisfy({ value.baseColor[$0].isFinite && (0...1).contains(value.baseColor[$0]) }),
            (0..<3).allSatisfy({ value.emissive[$0].isFinite && (0...1).contains(value.emissive[$0]) }),
            [value.metallic, value.roughness].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
            value.alphaCutoff.isFinite, value.alphaCutoff >= 0, Float(value.alphaCutoff).isFinite,
            (value.image == nil) == (source.image == nil)
        else { throw ImportedRenderError.invalidMaterial }
        let sampler = ImportedSamplerPlan(sampler: value.sampler)
        self.sampler = sampler
        image = try source.image.map { try ImportedRenderImage(source: $0, id: id, mipmapped: sampler.mip != .none) }
        alphaMode = value.alphaMode
        isDoubleSided = value.isDoubleSided
        let mode: Float
        switch value.alphaMode {
        case .opaque: mode = 0
        case .mask: mode = 1
        case .blend: mode = 2
        }
        uniforms = ImportedMaterialUniforms(
            baseColor: SIMD4(
                Float(value.baseColor.x), Float(value.baseColor.y), Float(value.baseColor.z), Float(value.baseColor.w)),
            emissiveMetallic: SIMD4(
                Float(value.emissive.x), Float(value.emissive.y), Float(value.emissive.z), Float(value.metallic)),
            parameters: SIMD4(Float(value.roughness), Float(value.alphaCutoff), mode, image == nil ? 0 : 1))
    }

    /// Unknown/generated bridges retain source colors without invented texture or model ownership.
    init() {
        uniforms = ImportedMaterialUniforms(
            baseColor: SIMD4(repeating: 1), emissiveMetallic: .zero, parameters: SIMD4(1, 0, 2, 0))
        alphaMode = .blend
        isDoubleSided = true
        sampler = ImportedSamplerPlan(sampler: nil)
        image = nil
    }
}

/// Pure preparation; source pixels stay source-encoded and vertex RGB becomes linear before interpolation.
struct ImportedRenderGeometry: Sendable {
    struct Vertex: Sendable {
        let position: SIMD4<Float>
        let normal: SIMD4<Float>
        let color: SIMD4<Float>
        let textureCoordinate: SIMD4<Float>
    }
    struct Triangle: Sendable {
        let firstVertex: UInt32
        let center: SIMD3<Float>
        let ordinal: Int
        let materialIndex: Int
        let isTransparent: Bool
    }
    let vertices: [Vertex]
    let triangles: [Triangle]
    /// Last entry is the explicit geometry-color fallback.
    let materials: [ImportedRenderMaterialPlan]
    let payloadBytes: Int

    init(data: ImportedMaterialRenderData, maximumPayloadBytes: Int = 256 * 1024 * 1024) throws {
        try Task.checkCancellation()
        guard (1...256 * 1024 * 1024).contains(maximumPayloadBytes) else { throw ImportedRenderError.invalidLimits }
        let source = data.surface.mesh.vertices
        let records = data.surface.triangles
        guard !source.isEmpty, source.count.isMultiple(of: 3), source.count <= Int(UInt32.max),
            records.count == source.count / 3,
            source.allSatisfy({ vertex in
                (0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite }
            })
        else { throw ImportedRenderError.invalidGeometry }
        guard data.materials.count == data.surface.modelIDs.count else { throw ImportedRenderError.invalidMaterial }
        guard data.materials.count <= ImportedRenderAdmission.maximumMaterials else {
            throw ImportedRenderError.bindingLimit
        }
        let bounds = try RenderBounds(vertices: source)
        var budget = ImportedRenderBudget(maximum: maximumPayloadBytes)
        try budget.charge(1, width: MemoryLayout<Self>.stride)
        try budget.charge(source.count, width: MemoryLayout<Vertex>.stride + MemoryLayout<UInt32>.stride)
        try budget.charge(records.count, width: MemoryLayout<Triangle>.stride)
        try budget.charge(data.materials.count + 1, width: MemoryLayout<ImportedRenderMaterialPlan>.stride)
        try budget.charge(4)  // Shared neutral sRGB texture for factor-only materials/fallback.
        var materials: [ImportedRenderMaterialPlan] = []
        materials.reserveCapacity(data.materials.count + 1)
        try budget.charge(
            materials.capacity - data.materials.count - 1, width: MemoryLayout<ImportedRenderMaterialPlan>.stride)
        for index in data.materials.indices {
            try Task.checkCancellation()
            let plan = try ImportedRenderMaterialPlan(source: data.materials[index], id: data.surface.modelIDs[index])
            try budget.charge(plan.image?.payloadBytes ?? 0)
            materials.append(plan)
        }
        let fallback = materials.count
        materials.append(ImportedRenderMaterialPlan())
        var vertices: [Vertex] = []
        var triangles: [Triangle] = []
        vertices.reserveCapacity(source.count)
        triangles.reserveCapacity(records.count)
        try budget.charge(vertices.capacity - source.count, width: MemoryLayout<Vertex>.stride)
        try budget.charge(triangles.capacity - records.count, width: MemoryLayout<Triangle>.stride)
        for (ordinal, record) in records.enumerated() {
            try Task.checkCancellation()
            let material = record.modelIndex ?? fallback
            guard material >= 0, material < materials.count,
                record.modelIndex == nil ? record.sourceUVs == nil : material < fallback,
                materials[material].image == nil || record.sourceUVs != nil
            else { throw ImportedRenderError.invalidGeometry }
            let offset = ordinal * 3
            for corner in 0..<3 {
                let color: SIMD4<Double>
                let uv: SIMD2<Double>
                switch corner {
                case 0:
                    color = record.colors.first
                    uv = record.sourceUVs?.first ?? .zero
                case 1:
                    color = record.colors.second
                    uv = record.sourceUVs?.second ?? .zero
                default:
                    color = record.colors.third
                    uv = record.sourceUVs?.third ?? .zero
                }
                let coordinate = SIMD2(Float(uv.x), Float(uv.y))
                guard uv.x.isFinite, uv.y.isFinite, coordinate.x.isFinite, coordinate.y.isFinite else {
                    throw ImportedRenderError.invalidGeometry
                }
                let original = source[offset + corner]
                vertices.append(
                    Vertex(
                        position: SIMD4((original.position - bounds.center) / bounds.radius, 1),
                        normal: SIMD4(original.normal, 0),
                        color: try Self.linear(color, encoding: record.colorEncoding),
                        textureCoordinate: SIMD4(coordinate.x, coordinate.y, record.sourceUVs == nil ? 0 : 1, 0)))
            }
            let center = (vertices[offset].position + vertices[offset + 1].position + vertices[offset + 2].position) / 3
            let transparent =
                record.modelIndex == nil
                ? record.colors.first.w < 1 || record.colors.second.w < 1 || record.colors.third.w < 1
                : materials[material].alphaMode == .blend
            triangles.append(
                Triangle(
                    firstVertex: UInt32(offset), center: SIMD3(center.x, center.y, center.z), ordinal: ordinal,
                    materialIndex: material, isTransparent: transparent))
        }
        try Task.checkCancellation()
        self.vertices = vertices
        self.triangles = triangles
        self.materials = materials
        payloadBytes = budget.used
    }

    private static func linear(_ source: SIMD4<Double>, encoding: ImportedSurfaceColorEncoding) throws -> SIMD4<Float> {
        guard (0..<4).allSatisfy({ source[$0].isFinite && (0...1).contains(source[$0]) }) else {
            throw ImportedRenderError.invalidGeometry
        }
        func channel(_ value: Double) -> Float {
            Float(encoding == .linear ? value : value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4))
        }
        return SIMD4(channel(source.x), channel(source.y), channel(source.z), Float(source.w))
    }

    func validateBufferLengths(maximumBufferLength: Int) throws {
        guard maximumBufferLength > 0, vertices.count <= maximumBufferLength / MemoryLayout<Vertex>.stride,
            vertices.count <= maximumBufferLength / MemoryLayout<UInt32>.stride
        else { throw ImportedRenderError.bufferLimit }
    }
}
