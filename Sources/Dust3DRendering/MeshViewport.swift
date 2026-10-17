import Dust3DKit
import MetalKit
import SwiftUI

/// Main-actor SwiftUI surface for a validated mesh and its interactive orbit camera.
public struct MeshViewport: NSViewRepresentable {
    let mesh: RenderMesh
    let isWireframe: Bool
    let cameraReset: Int
    let onError: (String) -> Void
    let meshRevision: Int

    /// Increment meshRevision to replace geometry; increment cameraReset to fit the view.
    /// GPU setup errors are delivered through onError on the main actor.
    public init(
        mesh: Mesh, isWireframe: Bool, cameraReset: Int, meshRevision: Int = 0, onError: @escaping (String) -> Void
    ) {
        self.mesh = .expanded(mesh)
        self.isWireframe = isWireframe
        self.cameraReset = cameraReset
        self.meshRevision = meshRevision
        self.onError = onError
    }

    /// Display copied indexed geometry; revision and camera-reset semantics match the expanded initializer.
    /// - Parameters:
    ///   - mesh: Immutable vertices and UInt32 triangle indices.
    ///   - isWireframe: Whether to draw triangle edges.
    ///   - cameraReset: Increment to fit the model again.
    ///   - meshRevision: Increment to replace GPU geometry while retaining orbit and zoom.
    ///   - onError: Receives GPU setup diagnostics on the main actor.
    public init(
        mesh: IndexedMesh, isWireframe: Bool, cameraReset: Int, meshRevision: Int = 0,
        onError: @escaping (String) -> Void
    ) {
        self.mesh = .indexed(mesh)
        self.isWireframe = isWireframe
        self.cameraReset = cameraReset
        self.meshRevision = meshRevision
        self.onError = onError
    }

    public func makeNSView(context: Context) -> InteractiveMeshView {
        let view = InteractiveMeshView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        return view
    }

    public func updateNSView(_ view: InteractiveMeshView, context: Context) {
        updateRenderer(in: view)
    }

    func updateRenderer(in view: InteractiveMeshView) {
        // A revision replaces GPU geometry while retaining the existing orbit camera.
        if (view.renderer == nil || view.meshRevision != meshRevision) && view.failedMeshRevision != meshRevision {
            do {
                guard let device = view.device else {
                    throw RendererError.unavailable("This Mac does not provide a Metal device.")
                }
                let renderer = try MeshRenderer(
                    mesh: mesh, device: device, colorPixelFormat: view.colorPixelFormat,
                    depthPixelFormat: view.depthStencilPixelFormat)
                if let camera = view.renderer?.camera { renderer.camera = camera }
                view.meshRevision = meshRevision
                view.failedMeshRevision = nil
                view.renderer = renderer
                view.delegate = renderer
            } catch {
                view.failedMeshRevision = meshRevision
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    guard view.failedMeshRevision == meshRevision else { return }
                    onError(message)
                }
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
/// AppKit event boundary owned by MeshViewport; geometry and camera remain renderer-owned.
public final class InteractiveMeshView: MTKView {
    var renderer: MeshRenderer?
    var meshRevision: Int?
    var failedMeshRevision: Int?
    var cameraReset = 0
    private var lastDragLocation: CGPoint?

    public override var acceptsFirstResponder: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragLocation = event.locationInWindow
    }

    public override func mouseDragged(with event: NSEvent) {
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

    public override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
    }

    public override func scrollWheel(with event: NSEvent) {
        renderer?.camera.zoom(delta: Float(event.scrollingDeltaY))
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
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
