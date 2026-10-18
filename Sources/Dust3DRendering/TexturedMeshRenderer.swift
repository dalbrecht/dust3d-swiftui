import AppKit
import MetalKit
import simd

/// Main-actor encoder owns transferred resources; CPU preparation/uploads run in the builder actor.
@MainActor
final class TexturedMeshRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        let transform: simd_float4x4
        let rotation: simd_float4x4
        let eye: SIMD4<Float>
        let options: SIMD4<Float>
    }

    private var resources: OwnedTexturedMetalResources
    private let builder = TexturedMetalResourcesBuilder()
    private var orderingTask: Task<Void, Never>?
    private var orderingRevision = 0
    private weak var presentationView: MTKView?
    private(set) var orderingError: (any Error)?
    private(set) var renderingError: (any Error)?
    private var hasRenderedFrame = false
    var onRendered: (() -> Void)?
    var onError: ((any Error) -> Void)?
    var isWireframe = false
    var camera: OrbitCamera {
        didSet {
            if oldValue.yaw != camera.yaw || oldValue.pitch != camera.pitch { updateOrdering() }
        }
    }

    init(resources: consuming OwnedTexturedMetalResources) {
        camera = resources.camera
        self.resources = resources
        super.init()
    }

    deinit { orderingTask?.cancel() }

    func waitForPendingOrdering() async { await orderingTask?.value }

    private func updateOrdering() {
        guard resources.order.transparentIndexCount > 0 else { return }
        orderingRevision += 1
        let revision = orderingRevision
        orderingTask?.cancel()
        let order = resources.order
        let rotation = camera.rotation
        let device = resources.device
        let builder = builder
        orderingTask = Task { [weak self] in
            do {
                let replacement = try await builder.reorder(order: order, rotation: rotation, device: device)
                try Task.checkCancellation()
                guard let self, self.orderingRevision == revision else { return }
                self.resources.transparentIndices = replacement.buffer
                self.orderingError = nil
                if let view = self.presentationView { view.setNeedsDisplay(view.bounds) }
            } catch is CancellationError {
                // A newer camera order supersedes this derived buffer; retain the last valid order.
            } catch {
                guard let self, self.orderingRevision == revision else { return }
                self.orderingError = error
                self.onError?(error)
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        presentationView = view
        guard view.colorPixelFormat == .bgra8Unorm_srgb, view.depthStencilPixelFormat == .depth32Float else {
            report(
                BakedMetalPreparationError.unavailable(
                    "The material renderer requires BGRA8 sRGB and depth32Float targets."))
            return
        }
        let background = NSColor.controlBackgroundColor.usingColorSpace(.deviceRGB) ?? .gray
        func linear(_ value: CGFloat) -> Double {
            let component = Double(value)
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        view.clearColor = MTLClearColorMake(
            linear(background.redComponent), linear(background.greenComponent), linear(background.blueComponent), 1)
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor else { return }
        guard let command = resources.queue.makeCommandBuffer(),
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)
        else {
            report(BakedMetalPreparationError.unavailable("Metal could not begin the material render pass."))
            return
        }
        encode(encoder: encoder, drawableSize: view.drawableSize)
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [weak self] completed in
            let error = completed.error
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.report(error)
                } else if self.renderingError == nil && !self.hasRenderedFrame {
                    self.hasRenderedFrame = true
                    self.onRendered?()
                }
            }
        }
        command.commit()
    }

    /// The same production pass is used by native presentation and offscreen acceptance.
    func encode(encoder: any MTLRenderCommandEncoder, drawableSize: CGSize) {
        let aspect = Float(drawableSize.width / max(drawableSize.height, 1))
        let boundedAspect = aspect.isFinite ? max(aspect, 0.01) : 1
        let distance = camera.distance / min(boundedAspect, 1)
        var uniforms = Uniforms(
            transform: camera.transform(aspect: aspect), rotation: camera.rotation,
            eye: SIMD4(0, 0, distance, 1), options: SIMD4(resources.normalMapEnabled ? 1 : 0, 0, 0, 0))
        encoder.setRenderPipelineState(resources.pipeline)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)
        encoder.setTriangleFillMode(isWireframe ? .lines : .fill)
        encoder.setVertexBuffer(resources.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentSamplerState(resources.sampler, index: 0)
        for (index, texture) in resources.textures.enumerated() { encoder.setFragmentTexture(texture, index: index) }
        if let indices = resources.opaqueIndices {
            encoder.setDepthStencilState(resources.opaqueDepth)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: resources.order.opaqueIndices.count, indexType: .uint32,
                indexBuffer: indices, indexBufferOffset: 0)
        }
        if let indices = resources.transparentIndices {
            encoder.setDepthStencilState(resources.transparentDepth)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: resources.order.transparentIndexCount, indexType: .uint32,
                indexBuffer: indices, indexBufferOffset: 0)
        }
    }

    private func report(_ error: any Error) {
        renderingError = error
        onError?(error)
    }
}
