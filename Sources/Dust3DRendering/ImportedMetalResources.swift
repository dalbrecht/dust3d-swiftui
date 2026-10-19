import Dust3DKit
import Foundation
import Metal
import simd

struct ImportedMetalMaterial {
    let uniforms: ImportedMaterialUniforms
    let isDoubleSided: Bool
    let texture: any MTLTexture
    let sampler: any MTLSamplerState
}

struct OwnedImportedMetalResources: ~Copyable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let pipeline: any MTLRenderPipelineState
    let opaqueDepth: any MTLDepthStencilState
    let transparentDepth: any MTLDepthStencilState
    let vertices: any MTLBuffer
    let opaqueIndices: (any MTLBuffer)?
    var transparentIndices: (any MTLBuffer)?
    var transparentBatches: [ImportedDrawBatch]
    let materials: [ImportedMetalMaterial]
    let order: ImportedTriangleOrder
    let camera: OrbitCamera
}
struct OwnedImportedDrawBuffer: ~Copyable {
    let buffer: (any MTLBuffer)?
    let batches: [ImportedDrawBatch]
}

/// Fresh GPU owners transfer once; validation, runtime compilation and uploads stay off the UI executor.
actor ImportedMetalResourcesBuilder {
    func make(
        data: ImportedMaterialRenderData, device: any MTLDevice, camera: OrbitCamera = OrbitCamera(),
        maximumPayloadBytes: Int = 256 * 1024 * 1024
    ) throws -> sending OwnedImportedMetalResources {
        try Self.prepare(data: data, device: device, camera: camera, maximumPayloadBytes: maximumPayloadBytes)
    }

    nonisolated private static func prepare(
        data: ImportedMaterialRenderData, device: any MTLDevice, camera: OrbitCamera,
        maximumPayloadBytes: Int
    ) throws -> sending OwnedImportedMetalResources {
        try Task.checkCancellation()
        let geometry = try ImportedRenderGeometry(data: data, maximumPayloadBytes: maximumPayloadBytes)
        try geometry.validateBufferLengths(maximumBufferLength: device.maxBufferLength)
        let order = try ImportedTriangleOrder(geometry: geometry)
        let transparent = try order.transparent(rotation: camera.rotation)
        let packaged = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("Dust3DNative_Dust3DRendering.bundle"))
        }
        guard let sourceURL = (packaged ?? Bundle.module).url(forResource: "Shaders", withExtension: "metal"),
            let queue = device.makeCommandQueue()
        else { throw ImportedRenderError.unavailable("Metal imported-material resources are unavailable.") }
        let options = MTLCompileOptions()
        if #available(macOS 15, *) { options.mathMode = .safe } else { options.fastMathEnabled = false }
        let library = try device.makeLibrary(source: String(contentsOf: sourceURL, encoding: .utf8), options: options)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "importedMeshVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "importedMeshFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.depthAttachmentPixelFormat = .depth32Float
        if let color = descriptor.colorAttachments[0] {
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .sourceAlpha
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        guard let vertices = try Self.buffer(geometry.vertices, device: device) else {
            throw ImportedRenderError.unavailable("Metal imported geometry is unavailable.")
        }
        let opaqueIndices = try Self.buffer(order.opaque.indices, device: device)
        let transparentIndices = try Self.buffer(transparent.indices, device: device)
        let opaqueDepth = try Self.depthState(device: device, writesDepth: true)
        let transparentDepth = try Self.depthState(device: device, writesDepth: false)
        let white = try Self.texture(device: device, width: 1, height: 1, mipmapped: false)
        try [UInt8](repeating: 255, count: 4).withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else {
                throw ImportedRenderError.unavailable("The neutral material sample is unreadable.")
            }
            white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: base, bytesPerRow: 4)
        }
        var materials: [ImportedMetalMaterial] = []
        var mipmaps: [any MTLTexture] = []
        for plan in geometry.materials {
            try Task.checkCancellation()
            let texture: any MTLTexture
            if let image = plan.image {
                texture = try Self.texture(
                    device: device, width: image.width, height: image.height, mipmapped: image.mipmapLevelCount > 1)
                try image.pixels.withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { throw ImportedRenderError.invalidImage }
                    texture.replace(
                        region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0, withBytes: base,
                        bytesPerRow: image.rowStride)
                }
                if image.mipmapLevelCount > 1 { mipmaps.append(texture) }
            } else {
                texture = white
            }
            let sampler = MTLSamplerDescriptor()
            sampler.normalizedCoordinates = true
            sampler.magFilter = plan.sampler.magnification == .nearest ? .nearest : .linear
            sampler.minFilter = plan.sampler.minification == .nearest ? .nearest : .linear
            switch plan.sampler.mip {
            case .none: sampler.mipFilter = .notMipmapped
            case .nearest: sampler.mipFilter = .nearest
            case .linear: sampler.mipFilter = .linear
            }
            sampler.sAddressMode = Self.address(plan.sampler.wrapS)
            sampler.tAddressMode = Self.address(plan.sampler.wrapT)
            guard let state = device.makeSamplerState(descriptor: sampler) else {
                throw ImportedRenderError.unavailable("Metal could not allocate an imported sampler.")
            }
            materials.append(
                ImportedMetalMaterial(
                    uniforms: plan.uniforms, isDoubleSided: plan.isDoubleSided, texture: texture, sampler: state))
        }
        if !mipmaps.isEmpty {
            guard let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
                throw ImportedRenderError.unavailable("Metal could not begin imported mipmap generation.")
            }
            do {
                defer { blit.endEncoding() }
                for texture in mipmaps {
                    try Task.checkCancellation()
                    blit.generateMipmaps(for: texture)
                }
            }
            command.commit()
            command.waitUntilCompleted()
            if let error = command.error { throw error }
            guard command.status == .completed else {
                throw ImportedRenderError.unavailable("Imported mipmap generation did not complete.")
            }
        }
        try Task.checkCancellation()
        return OwnedImportedMetalResources(
            device: device, queue: queue, pipeline: pipeline, opaqueDepth: opaqueDepth,
            transparentDepth: transparentDepth, vertices: vertices, opaqueIndices: opaqueIndices,
            transparentIndices: transparentIndices, transparentBatches: transparent.batches, materials: materials,
            order: order, camera: camera)
    }

    func reorder(order: ImportedTriangleOrder, rotation: simd_float4x4, device: any MTLDevice) throws
        -> sending OwnedImportedDrawBuffer
    {
        let draws = try order.transparent(rotation: rotation)
        let buffer = try Self.buffer(draws.indices, device: device)
        try Task.checkCancellation()
        return OwnedImportedDrawBuffer(buffer: buffer, batches: draws.batches)
    }

    nonisolated private static func texture(device: any MTLDevice, width: Int, height: Int, mipmapped: Bool) throws
        -> sending any MTLTexture
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: mipmapped)
        descriptor.usage = .shaderRead
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let value = device.makeTexture(descriptor: descriptor) else {
            throw ImportedRenderError.unavailable("Metal could not allocate an imported source texture.")
        }
        return value
    }

    private static func address(_ mode: ImportedTextureWrapMode) -> MTLSamplerAddressMode {
        switch mode {
        case .repeatTexture: .repeat
        case .clampToEdge: .clampToEdge
        case .mirroredRepeat: .mirrorRepeat
        }
    }

    nonisolated private static func buffer<Element: Sendable>(_ values: [Element], device: any MTLDevice) throws
        -> sending (any MTLBuffer)?
    {
        guard !values.isEmpty else { return nil }
        try Task.checkCancellation()
        guard
            let result = values.withUnsafeBytes({ bytes in
                bytes.baseAddress.flatMap {
                    device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared)
                }
            })
        else { throw ImportedRenderError.unavailable("Metal could not allocate an imported draw buffer.") }
        return result
    }

    nonisolated private static func depthState(device: any MTLDevice, writesDepth: Bool) throws
        -> sending any MTLDepthStencilState
    {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = writesDepth
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
            throw ImportedRenderError.unavailable("Metal imported depth testing is unavailable.")
        }
        return state
    }
}
