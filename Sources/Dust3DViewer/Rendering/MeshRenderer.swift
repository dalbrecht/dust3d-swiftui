import AppKit
import Dust3DKit
import MetalKit
import simd

@MainActor
final class MeshRenderer: NSObject, MTKViewDelegate {
    private struct GPUVertex {
        let position: SIMD4<Float>
        let normal: SIMD4<Float>
        let color: SIMD4<Float>
    }

    private struct Uniforms {
        var transform: simd_float4x4
        var rotation: simd_float4x4
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let buffer: MTLBuffer
    private let vertexCount: Int
    var camera = OrbitCamera()
    var isWireframe = false

    init(mesh: Mesh, view: MTKView, device: MTLDevice) throws {
        let packagedResources = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("Dust3DNative_Dust3DViewer.bundle"))
        }
        guard let queue = device.makeCommandQueue(),
            let shaderURL = (packagedResources ?? Bundle.module).url(forResource: "Shaders", withExtension: "metal")
        else { throw RendererError.unavailable("Metal resources are unavailable.") }
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "meshVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "meshFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RendererError.unavailable("Metal depth testing is unavailable.")
        }
        let positions = mesh.vertices.map(\.position)
        let minimum = positions.reduce(SIMD3<Float>(repeating: .infinity), simd_min)
        let maximum = positions.reduce(SIMD3<Float>(repeating: -.infinity), simd_max)
        let center = (minimum + maximum) * 0.5
        let radius = max(simd_length(maximum - minimum) * 0.5, 0.001)
        let vertices = mesh.vertices.map { vertex in
            GPUVertex(
                position: SIMD4((vertex.position - center) / radius, 1),
                normal: SIMD4(vertex.normal, 0),
                color: vertex.color
            )
        }
        guard
            let buffer = vertices.withUnsafeBytes({ bytes in
                bytes.baseAddress.flatMap {
                    device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared)
                }
            })
        else { throw RendererError.unavailable("Metal could not allocate a vertex buffer.") }
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
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setTriangleFillMode(isWireframe ? .lines : .fill)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        var uniforms = Uniforms(
            transform: camera.transform(aspect: Float(view.drawableSize.width / max(view.drawableSize.height, 1))),
            rotation: camera.rotation
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}

enum RendererError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}
