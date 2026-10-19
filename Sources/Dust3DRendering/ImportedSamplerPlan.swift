import Dust3DKit

/// Pure glTF sampler policy. Unspecified filtering uses trilinear minification and linear magnification.
struct ImportedSamplerPlan: Sendable, Equatable {
    enum Filter: Sendable { case nearest, linear }
    enum MipFilter: Sendable { case none, nearest, linear }
    let magnification: Filter
    let minification: Filter
    let mip: MipFilter
    let wrapS: ImportedTextureWrapMode
    let wrapT: ImportedTextureWrapMode

    init(sampler: ImportedTextureSampler?) {
        magnification = sampler?.magnification == .nearest ? .nearest : .linear
        switch sampler?.minification ?? .linearMipmapLinear {
        case .nearest:
            minification = .nearest
            mip = .none
        case .linear:
            minification = .linear
            mip = .none
        case .nearestMipmapNearest:
            minification = .nearest
            mip = .nearest
        case .linearMipmapNearest:
            minification = .linear
            mip = .nearest
        case .nearestMipmapLinear:
            minification = .nearest
            mip = .linear
        case .linearMipmapLinear:
            minification = .linear
            mip = .linear
        }
        wrapS = sampler?.wrapS ?? .repeatTexture
        wrapT = sampler?.wrapT ?? .repeatTexture
    }
}
