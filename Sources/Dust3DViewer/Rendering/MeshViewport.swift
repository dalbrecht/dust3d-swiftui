import Dust3DKit
import MetalKit
import SwiftUI

struct MeshViewport: NSViewRepresentable {
    let mesh: Mesh
    let isWireframe: Bool
    let cameraReset: Int
    let onError: (String) -> Void

    func makeNSView(context: Context) -> InteractiveMeshView {
        let view = InteractiveMeshView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        return view
    }

    func updateNSView(_ view: InteractiveMeshView, context: Context) {
        // A successful load creates a fresh vertex array; SwiftUI recreates this
        // representable by mesh identity in ContentView.
        if view.renderer == nil && !view.hasReportedError {
            do {
                guard let device = view.device else {
                    throw RendererError.unavailable("This Mac does not provide a Metal device.")
                }
                let renderer = try MeshRenderer(mesh: mesh, view: view, device: device)
                view.renderer = renderer
                view.delegate = renderer
            } catch {
                view.hasReportedError = true
                let message = error.localizedDescription
                DispatchQueue.main.async { onError(message) }
                return
            }
        }
        if view.cameraReset != cameraReset {
            view.renderer?.camera = OrbitCamera()
            view.cameraReset = cameraReset
        }
        view.renderer?.isWireframe = isWireframe
        view.needsDisplay = true
    }
}

@MainActor
final class InteractiveMeshView: MTKView {
    var renderer: MeshRenderer?
    var hasReportedError = false
    var cameraReset = 0
    private var lastDragLocation: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        let location = event.locationInWindow
        if let previous = lastDragLocation {
            renderer?.camera.orbit(
                horizontal: Float(location.x - previous.x),
                vertical: Float(previous.y - location.y)
            )
        }
        lastDragLocation = location
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
    }

    override func scrollWheel(with event: NSEvent) {
        renderer?.camera.zoom(delta: Float(event.scrollingDeltaY))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: renderer?.camera.orbit(horizontal: -10, vertical: 0)
        case 124: renderer?.camera.orbit(horizontal: 10, vertical: 0)
        case 125: renderer?.camera.orbit(horizontal: 0, vertical: 10)
        case 126: renderer?.camera.orbit(horizontal: 0, vertical: -10)
        case 3: renderer?.camera = OrbitCamera()  // F: fit model.
        default: super.keyDown(with: event)
        }
        needsDisplay = true
    }
}
