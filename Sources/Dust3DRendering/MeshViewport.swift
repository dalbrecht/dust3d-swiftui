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
    let bakedMesh: MeshWithBakedTextures?
    let onMaterialError: (String) -> Void

    /// Increment meshRevision to replace geometry; increment cameraReset to fit the view.
    /// GPU setup errors are delivered through onError on the main actor.
    public init(
        mesh: Mesh, isWireframe: Bool, cameraReset: Int, meshRevision: Int = 0, onError: @escaping (String) -> Void
    ) {
        bakedMesh = nil
        onMaterialError = { _ in }
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
    ///   - bakedMesh: Optional baked geometry/maps paired with this mesh revision. Uploads in the background.
    ///   - onMaterialError: Receives optional material failures; defaults to onError. Ordinary geometry remains available.
    ///   - onError: Receives ordinary GPU setup diagnostics on the main actor.
    public init(
        mesh: IndexedMesh, isWireframe: Bool, cameraReset: Int, meshRevision: Int = 0,
        bakedMesh: MeshWithBakedTextures? = nil, onMaterialError: ((String) -> Void)? = nil,
        onError: @escaping (String) -> Void
    ) {
        self.bakedMesh = bakedMesh
        self.onMaterialError = onMaterialError ?? onError
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

    public static func dismantleNSView(_ view: InteractiveMeshView, coordinator: ()) {
        view.cancelMaterialUpload()
        view.delegate = nil
    }

    func updateRenderer(in view: InteractiveMeshView) {
        if bakedMesh == nil || view.meshRevision != meshRevision {
            view.cancelMaterialUpload()
            view.materialRenderer = nil
            view.colorPixelFormat = .bgra8Unorm
            view.delegate = view.renderer
        }
        // A revision replaces GPU geometry while retaining the existing orbit camera.
        if (view.renderer == nil || view.meshRevision != meshRevision) && view.failedMeshRevision != meshRevision {
            do {
                guard let device = view.device else {
                    throw RendererError.unavailable("This Mac does not provide a Metal device.")
                }
                let renderer = try MeshRenderer(
                    mesh: mesh, device: device, colorPixelFormat: view.colorPixelFormat,
                    depthPixelFormat: view.depthStencilPixelFormat)
                renderer.camera = view.orbitCamera
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
            view.orbitCamera = OrbitCamera()
            view.cameraReset = cameraReset
        }
        view.renderer?.isWireframe = isWireframe
        view.materialRenderer?.isWireframe = isWireframe
        view.requestedWireframe = isWireframe
        if let bakedMesh {
            view.updateMaterials(bakedMesh, revision: meshRevision, onError: onMaterialError)
        }
        view.needsDisplay = true
    }
}

@MainActor
/// AppKit event boundary owned by MeshViewport; geometry and camera remain renderer-owned.
public class InteractiveMeshView: MTKView {
    var renderer: MeshRenderer?
    var materialRenderer: TexturedMeshRenderer?
    var materialTask: Task<Void, Never>?
    var requestedMaterialRevision: Int?
    var completedMaterialRevision: Int?
    var failedMaterialRevision: Int?
    var requestedWireframe = false
    let materialBuilder = TexturedMetalResourcesBuilder()

    var orbitCamera: OrbitCamera {
        get { materialRenderer?.camera ?? renderer?.camera ?? OrbitCamera() }
        set {
            renderer?.camera = newValue
            materialRenderer?.camera = newValue
        }
    }

    func cancelMaterialUpload() {
        materialTask?.cancel()
        materialTask = nil
        requestedMaterialRevision = nil
        completedMaterialRevision = nil
        failedMaterialRevision = nil
    }

    func updateMaterials(_ baked: MeshWithBakedTextures, revision: Int, onError: @escaping (String) -> Void) {
        guard requestedMaterialRevision != revision, completedMaterialRevision != revision,
            failedMaterialRevision != revision
        else { return }
        materialTask?.cancel()
        requestedMaterialRevision = revision
        let camera = orbitCamera
        let builder = materialBuilder
        let device = device
        materialTask = Task { [weak self] in
            do {
                guard let device else {
                    throw BakedMetalPreparationError.unavailable("This Mac does not provide a Metal device.")
                }
                let resources = try await builder.make(bakedMesh: baked, device: device, camera: camera)
                try Task.checkCancellation()
                guard let self, self.requestedMaterialRevision == revision, self.meshRevision == revision else {
                    return
                }
                let renderer = TexturedMeshRenderer(resources: resources)
                renderer.camera = self.orbitCamera
                renderer.isWireframe = self.requestedWireframe
                renderer.onError = { [weak self] error in
                    guard let self, self.completedMaterialRevision == revision else { return }
                    onError(error.localizedDescription)
                }
                self.materialRenderer = renderer
                self.completedMaterialRevision = revision
                self.requestedMaterialRevision = nil
                self.colorPixelFormat = .bgra8Unorm_srgb
                self.delegate = renderer
                self.setNeedsDisplay(self.bounds)
                // Paused MTKViews must present the accepted upload without waiting for another SwiftUI update.
                self.draw()
            } catch is CancellationError {
                // A replacement or detached view owns presentation now.
            } catch {
                guard let self, self.requestedMaterialRevision == revision, self.meshRevision == revision else {
                    return
                }
                self.failedMaterialRevision = revision
                self.requestedMaterialRevision = nil
                onError(error.localizedDescription)
            }
        }
    }

    deinit { materialTask?.cancel() }
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
            orbitCamera.orbit(
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
        orbitCamera.zoom(delta: Float(event.scrollingDeltaY))
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: orbitCamera.orbit(horizontal: -10, vertical: 0)
        case 124: orbitCamera.orbit(horizontal: 10, vertical: 0)
        case 125: orbitCamera.orbit(horizontal: 0, vertical: 10)
        case 126: orbitCamera.orbit(horizontal: 0, vertical: -10)
        case 3: orbitCamera = OrbitCamera()  // F: fit model.
        default: super.keyDown(with: event)
        }
        needsDisplay = true
    }
}
