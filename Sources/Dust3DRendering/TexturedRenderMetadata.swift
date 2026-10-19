import Dust3DKit

/// Both baked contracts share the upload/encoder while retaining their own source metadata.
enum TexturedMaterialInput: Sendable {
    case legacy(MeshWithBakedTextures)
    case source(SourceBakedMesh)
}

/// Preserve the actual source contract; imported bakes do not have legacy chart metadata.
enum TexturedRenderMetadata: Sendable, Equatable {
    case legacy(MeshUvMetadata)
    case source([SourceBakedTriangle], [ImportedSurfaceIdentity], [ImportedSurfaceComponent])

    var triangleCount: Int {
        switch self {
        case .legacy(let metadata): return metadata.triangles.count
        case .source(let triangles, _, _): return triangles.count
        }
    }

    func hasMapping(at index: Int) -> Bool {
        switch self {
        case .legacy(let metadata): return metadata.triangles[index].hasMapping
        case .source(let triangles, _, _): return triangles[index].packedUVs != nil
        }
    }

    func policy(at index: Int) -> SourceBakedPolicy? {
        switch self {
        case .legacy: return nil
        case .source(let triangles, _, _): return triangles[index].policy
        }
    }
}

struct TexturedInputTriangle {
    let corners: (first: SIMD2<Double>, second: SIMD2<Double>, third: SIMD2<Double>)
    let hasMapping: Bool
    let tangent: MeshTextureTangent
    let componentKind: UInt32
    let componentIndex: Int?
    let modelIndex: Int?

    init(legacy: MeshUvTriangle, tangent: MeshTextureTangent) {
        corners = (legacy.corners.first, legacy.corners.second, legacy.corners.third)
        hasMapping = legacy.hasMapping
        self.tangent = tangent
        switch legacy.component.kind {
        case .unknown: componentKind = 0
        case .component: componentKind = 1
        case .ambiguous: componentKind = 2
        case .unrecognized(let value): componentKind = value
        }
        componentIndex = legacy.component.identityIndex
        modelIndex = nil
    }

    init(source: SourceBakedTriangle, models: Int, components: Int) throws {
        guard source.modelIndex.map({ (0..<models).contains($0) }) ?? true,
            source.componentIndex.map({ (0..<components).contains($0) }) ?? true
        else {
            throw TexturedRenderGeometryError.invalidSourceMetadata
        }
        if let policy = source.policy {
            guard policy.alphaCutoff.isFinite, policy.alphaCutoff >= 0 else {
                throw TexturedRenderGeometryError.invalidSourceMetadata
            }
        }
        if let uv = source.packedUVs {
            corners = (uv.first, uv.second, uv.third)
        } else {
            corners = (.zero, .zero, .zero)
        }
        hasMapping = source.packedUVs != nil
        tangent = source.tangent
        componentKind = source.componentIndex == nil ? 0 : 1
        componentIndex = source.componentIndex
        modelIndex = source.modelIndex
    }
}

/// Pure map-role transformation shared by every source-aware rendering entry point.
extension SourceBakedMipmaps {
    var materialUploadSlots: [Int: TextureMipChain] {
        let maps = [color, normal, metallic, roughness, emissive]
        return Dictionary(
            uniqueKeysWithValues: maps.enumerated().compactMap { slot, chain in
                chain.map { (slot, $0) }
            })
    }
}
