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

    private let alphaPolicy: MeshAlphaPolicy
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let buffer: MTLBuffer
    private let vertexCount: Int
    private let indexBuffer: MTLBuffer?
    private let indexCount: Int
    var camera = OrbitCamera()
    var isWireframe = false
    var showsColor = true

    convenience init(
        mesh: RenderMesh, device: MTLDevice,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm, depthPixelFormat: MTLPixelFormat = .depth32Float,
        blendsVertexAlpha: Bool = false
    ) throws {
        try self.init(
            geometry: RenderGeometry(mesh: mesh), device: device,
            colorPixelFormat: colorPixelFormat, depthPixelFormat: depthPixelFormat,
            blendsVertexAlpha: blendsVertexAlpha)
    }

    init(
        geometry: RenderGeometry, device: MTLDevice,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm, depthPixelFormat: MTLPixelFormat = .depth32Float,
        blendsVertexAlpha: Bool = false
    ) throws {
        alphaPolicy = blendsVertexAlpha ? .vertexAlpha : .opaque
        try geometry.validateBufferLengths(maximumBufferLength: device.maxBufferLength)
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
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RendererError.unavailable("Metal depth testing is unavailable.")
        }
        let vertices = geometry.vertices
        guard
            let buffer = vertices.withUnsafeBytes({ bytes in
                bytes.baseAddress.flatMap {
                    device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared)
                }
            })
        else { throw RendererError.unavailable("Metal could not allocate a vertex buffer.") }
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
        self.queue = queue
        self.depthState = depthState
        self.buffer = buffer
        vertexCount = vertices.count
        super.init()
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
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setTriangleFillMode(isWireframe ? .lines : .fill)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        var uniforms = Uniforms(
            transform: camera.transform(aspect: Float(drawableSize.width / max(drawableSize.height, 1))),
            rotation: camera.rotation, options: SIMD4(0, showsColor ? 0 : 1, alphaPolicy.shaderOption, 0)
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        if let indexBuffer {
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: indexCount, indexType: .uint32,
                indexBuffer: indexBuffer, indexBufferOffset: 0)
        } else {
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }
    }
}

extension RendererError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}
