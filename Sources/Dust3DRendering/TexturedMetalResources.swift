import Dust3DKit
import Foundation
import Metal
import simd

/// Noncopyable CPU owner; fresh non-Sendable Metal resources transfer through `sending`.
struct OwnedTexturedMetalResources: ~Copyable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let pipeline: any MTLRenderPipelineState
    let opaqueDepth: any MTLDepthStencilState
    let transparentDepth: any MTLDepthStencilState
    let sampler: any MTLSamplerState
    let vertices: any MTLBuffer
    let opaqueIndices: (any MTLBuffer)?
    var transparentIndices: (any MTLBuffer)?
    let textures: [any MTLTexture]
    let order: BakedTriangleOrder
    let normalMapEnabled: Bool
    let camera: OrbitCamera
}

struct OwnedTexturedIndexBuffer: ~Copyable {
    let buffer: (any MTLBuffer)?
}

/// Shader compilation, CPU preparation and uploads run away from the UI executor.
/// No mutable buffer/texture alias is retained after the ownership transfer.
actor TexturedMetalResourcesBuilder {
    func make(
        bakedMesh: MeshWithBakedTextures, device: any MTLDevice,
        camera: OrbitCamera = OrbitCamera(), maximumPayloadBytes: Int = 256 * 1024 * 1024
    ) throws -> sending OwnedTexturedMetalResources {
        try Task.checkCancellation()
        let geometry = try TexturedRenderGeometry(bakedMesh: bakedMesh, maximumPayloadBytes: maximumPayloadBytes)
        let plan = try BakedMetalUploadPlan(
            geometry: geometry, maximumBufferLength: device.maxBufferLength, maximumPayloadBytes: maximumPayloadBytes)
        let order = try BakedTriangleOrder(geometry: geometry, hasTransparentColor: plan.hasTransparentColor)
        let sorted = try order.transparentIndices(rotation: camera.rotation)
        let packaged = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("Dust3DNative_Dust3DRendering.bundle"))
        }
        guard let shaderURL = (packaged ?? Bundle.module).url(forResource: "Shaders", withExtension: "metal"),
            let queue = device.makeCommandQueue()
        else { throw BakedMetalPreparationError.unavailable("Metal material resources are unavailable.") }
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let options = MTLCompileOptions()
        if #available(macOS 15, *) { options.mathMode = .safe } else { options.fastMathEnabled = false }
        let library = try device.makeLibrary(source: source, options: options)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "bakedMeshVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "bakedMeshFragment")
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
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor),
            let vertices = try Self.buffer(geometry.vertices, device: device)
        else { throw BakedMetalPreparationError.unavailable("Metal material buffers are unavailable.") }
        let opaque = try Self.buffer(order.opaqueIndices, device: device)
        let transparent = try Self.buffer(sorted, device: device)
        let opaqueDepth = try depthState(device: device, writesDepth: true)
        let transparentDepth = try depthState(device: device, writesDepth: false)
        var textures: [any MTLTexture] = []
        for image in plan.images {
            try Task.checkCancellation()
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: image.pixelFormat, width: image.width, height: image.height, mipmapped: false)
            descriptor.usage = .shaderRead
            descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw BakedMetalPreparationError.unavailable("Metal could not allocate a material texture.")
            }
            try image.pixels.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else {
                    throw BakedMetalPreparationError.unavailable("A material texture has no readable samples.")
                }
                texture.replace(
                    region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                    withBytes: base, bytesPerRow: image.rowStride)
            }
            textures.append(texture)
        }
        try Task.checkCancellation()
        return OwnedTexturedMetalResources(
            device: device, queue: queue, pipeline: pipeline, opaqueDepth: opaqueDepth,
            transparentDepth: transparentDepth, sampler: sampler, vertices: vertices,
            opaqueIndices: opaque, transparentIndices: transparent, textures: textures, order: order,
            normalMapEnabled: plan.normalMapEnabled, camera: camera)
    }

    func reorder(order: BakedTriangleOrder, rotation: simd_float4x4, device: any MTLDevice) throws
        -> sending OwnedTexturedIndexBuffer
    {
        let indices = try order.transparentIndices(rotation: rotation)
        let result = try Self.buffer(indices, device: device)
        try Task.checkCancellation()
        return OwnedTexturedIndexBuffer(buffer: result)
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
        else { throw BakedMetalPreparationError.unavailable("Metal could not allocate a material geometry buffer.") }
        return result
    }

    private func depthState(device: any MTLDevice, writesDepth: Bool) throws -> any MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = writesDepth
        guard let result = device.makeDepthStencilState(descriptor: descriptor) else {
            throw BakedMetalPreparationError.unavailable("Metal material depth testing is unavailable.")
        }
        return result
    }
}
