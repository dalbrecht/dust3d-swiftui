import AppKit
import Dust3DKit
import MetalKit
import simd

/// Each policy transition owns queued renderer diagnostics, including A-to-B-to-A changes.
struct MeshAlphaRequestState {
    private(set) var blendsVertexAlpha: Bool?
    private(set) var epoch = UUID()

    mutating func update(blendsVertexAlpha: Bool) -> Bool {
        guard self.blendsVertexAlpha != blendsVertexAlpha else { return false }
        self.blendsVertexAlpha = blendsVertexAlpha
        epoch = UUID()
        return true
    }

    func accepts(_ capturedEpoch: UUID) -> Bool { epoch == capturedEpoch }
}

/// Ordinary meshes stay opaque; rest-rig previews opt into Qt's straight-alpha pass.
enum MeshAlphaPolicy: Sendable {
    case opaque
    case vertexAlpha

    var shaderOption: Float { self == .vertexAlpha ? 1 : 0 }

    func configure(_ attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = self == .vertexAlpha
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }
}

@MainActor
final class MeshRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var transform: simd_float4x4
        var rotation: simd_float4x4
        var options: SIMD4<Float>
    }

    private struct GeometryBuffers {
        let buffer: MTLBuffer
        let vertexCount: Int
        let indexBuffer: MTLBuffer?
        let indexCount: Int

        init(geometry: RenderGeometry, device: MTLDevice) throws {
            try geometry.validateBufferLengths(maximumBufferLength: device.maxBufferLength)
            let vertices = geometry.vertices
            guard
                let buffer = vertices.withUnsafeBytes({ bytes in
                    bytes.baseAddress.flatMap {
                        device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared)
                    }
                })
            else { throw RendererError.unavailable("Metal could not allocate a vertex buffer.") }
            self.buffer = buffer
            vertexCount = vertices.count
            if let indices = geometry.indices {
                guard
                    let indexBuffer = indices.withUnsafeBytes({ bytes in
                        bytes.baseAddress.flatMap {
                            device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared)
                        }
                    })
                else { throw RendererError.unavailable("Metal could not allocate an index buffer.") }
                self.indexBuffer = indexBuffer
                indexCount = indices.count
            } else {
                indexBuffer = nil
                indexCount = 0
            }
        }
    }

    private struct GroundUniforms {
        var transform: simd_float4x4
        var rotation: simd_float4x4
        var centerAndRadius: SIMD4<Float>
        var phase: SIMD2<Float>
    }

    private let animationGround: (pipeline: MTLRenderPipelineState, bounds: RenderBounds)?
    var animationGroundOffset: SIMD2<Double>?

    private let alphaPolicy: MeshAlphaPolicy
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var buffers: GeometryBuffers
    private var drawRange = MeshDrawRangeState()
    var camera = OrbitCamera()
    var isWireframe = false
    var showsColor = true

    convenience init(
        mesh: RenderMesh, device: MTLDevice,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm, depthPixelFormat: MTLPixelFormat = .depth32Float,
        blendsVertexAlpha: Bool = false, referenceBounds: RenderBounds? = nil
    ) throws {
        try self.init(
            geometry: RenderGeometry(mesh: mesh, referenceBounds: referenceBounds), device: device,
            colorPixelFormat: colorPixelFormat, depthPixelFormat: depthPixelFormat,
            blendsVertexAlpha: blendsVertexAlpha, referenceBounds: referenceBounds)
    }

    init(
        geometry: RenderGeometry, device: MTLDevice,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm, depthPixelFormat: MTLPixelFormat = .depth32Float,
        blendsVertexAlpha: Bool = false, referenceBounds: RenderBounds? = nil
    ) throws {
        alphaPolicy = blendsVertexAlpha ? .vertexAlpha : .opaque
        let packagedResources = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("Dust3DNative_Dust3DRendering.bundle"))
        }
        guard let queue = device.makeCommandQueue(),
            let shaderURL = (packagedResources ?? Bundle.module).url(forResource: "Shaders", withExtension: "metal")
        else { throw RendererError.unavailable("Metal resources are unavailable.") }
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "meshVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "meshFragment")
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        alphaPolicy.configure(descriptor.colorAttachments[0])
        descriptor.depthAttachmentPixelFormat = depthPixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        animationGround = try referenceBounds.map { bounds in
            let groundDescriptor = MTLRenderPipelineDescriptor()
            groundDescriptor.vertexFunction = library.makeFunction(name: "animationGroundVertex")
            groundDescriptor.fragmentFunction = library.makeFunction(name: "animationGroundFragment")
            groundDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            groundDescriptor.depthAttachmentPixelFormat = depthPixelFormat
            return (try device.makeRenderPipelineState(descriptor: groundDescriptor), bounds)
        }
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RendererError.unavailable("Metal depth testing is unavailable.")
        }
        self.queue = queue
        self.depthState = depthState
        buffers = try GeometryBuffers(geometry: geometry, device: device)
        try drawRange.update(vertexCount: buffers.vertexCount, range: nil, isIndexed: buffers.indexBuffer != nil)
        super.init()
    }

    /// Publish the pose and ground only after the replacement is ready to draw.
    func replaceAnimationFrame(mesh: Mesh, groundOffset: SIMD2<Double>) throws {
        guard let animationGround, groundOffset.x.isFinite, groundOffset.y.isFinite else {
            throw RendererError.unavailable("The animation ground position is unavailable.")
        }
        let geometry = try RenderGeometry(mesh: .expanded(mesh), referenceBounds: animationGround.bounds)
        let replacement = try GeometryBuffers(geometry: geometry, device: queue.device)
        var range = MeshDrawRangeState()
        try range.update(vertexCount: replacement.vertexCount, range: nil, isIndexed: false)
        buffers = replacement
        drawRange = range
        animationGroundOffset = groundOffset
    }

    /// Select triangles from the existing full buffer without changing normalization.
    func updateDrawRange(_ range: Range<Int>?) throws {
        try drawRange.update(vertexCount: buffers.vertexCount, range: range, isIndexed: buffers.indexBuffer != nil)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let background = NSColor.controlBackgroundColor.usingColorSpace(.deviceRGB) ?? .gray
        view.clearColor = MTLClearColorMake(
            background.redComponent, background.greenComponent, background.blueComponent, 1)
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
            let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        encode(encoder: encoder, drawableSize: view.drawableSize)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    /// Encodes the same production pass for either an MTKView drawable or an offscreen test target.
    func encode(encoder: MTLRenderCommandEncoder, drawableSize: CGSize) {
        guard drawRange.isValid else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setTriangleFillMode(isWireframe ? .lines : .fill)
        encoder.setVertexBuffer(buffers.buffer, offset: 0, index: 0)
        var uniforms = Uniforms(
            transform: camera.transform(aspect: Float(drawableSize.width / max(drawableSize.height, 1))),
            rotation: camera.rotation, options: SIMD4(0, showsColor ? 0 : 1, alphaPolicy.shaderOption, 0)
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        if let indexBuffer = buffers.indexBuffer {
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: buffers.indexCount, indexType: .uint32,
                indexBuffer: indexBuffer, indexBufferOffset: 0)
        } else if drawRange.span.vertexCount > 0 {
            encoder.drawPrimitives(
                type: .triangle, vertexStart: drawRange.span.vertexStart, vertexCount: drawRange.span.vertexCount)
        }
        encodeAnimationGround(encoder: encoder, transform: uniforms.transform, rotation: uniforms.rotation)
    }

    private func encodeAnimationGround(
        encoder: MTLRenderCommandEncoder, transform: simd_float4x4, rotation: simd_float4x4
    ) {
        guard let animationGround, let offset = animationGroundOffset else { return }
        // Rotate in world units, then keep one checker period before converting to Float.
        let x = Double(rotation.columns.0.x) * offset.x + Double(rotation.columns.2.x) * offset.y
        let z = Double(rotation.columns.0.z) * offset.x + Double(rotation.columns.2.z) * offset.y
        guard x.isFinite, z.isFinite else { return }
        var uniforms = GroundUniforms(
            transform: transform, rotation: rotation,
            centerAndRadius: SIMD4(animationGround.bounds.center, animationGround.bounds.radius),
            phase: SIMD2(Float(x.truncatingRemainder(dividingBy: 1)), Float(z.truncatingRemainder(dividingBy: 1))))
        encoder.setRenderPipelineState(animationGround.pipeline)
        encoder.setTriangleFillMode(.fill)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GroundUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
}

extension RendererError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}
