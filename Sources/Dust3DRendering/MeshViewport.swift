import Dust3DKit
import MetalKit
import SwiftUI

/// Mutually exclusive immutable material representation for one current mesh revision.
public enum MeshMaterialContent: Sendable {
    case baked(MeshWithBakedTextures)
    /// Source-aware packed maps with per-triangle alpha/sidedness and an atlas LOD restriction.
    case sourceBaked(SourceBakedMesh)
    case imported(ImportedMaterialRenderData)
}

extension MeshMaterialContent {
    /// Preparation diagnostics remain available after a GPU error, independent of displayed-material admission.
    package var preparationWarning: String? {
        switch self {
        case .baked(let value): return value.geometry.warning
        case .sourceBaked(let value): return value.geometry.warning
        case .imported: return nil
        }
    }
}

/// Main-actor SwiftUI surface for a validated mesh and its interactive orbit camera.
public struct MeshViewport: NSViewRepresentable {
    let mesh: RenderMesh
    let isWireframe: Bool
    let showsColor: Bool
    let automaticallyOrbits: Bool
    let cameraReset: Int
    let cameraCommand: MeshCameraCommand?
    let onError: (String) -> Void
    let meshRevision: Int
    let materials: MeshMaterialContent?
    let onMaterialRendered: () -> Void
    let onMaterialError: (String) -> Void

    /// Increment meshRevision to replace geometry; increment cameraReset to fit the view.
    /// GPU setup errors are delivered through onError on the main actor.
    public init(
        mesh: Mesh, isWireframe: Bool, cameraReset: Int, meshRevision: Int = 0,
        cameraCommand: MeshCameraCommand? = nil, showsColor: Bool = true, automaticallyOrbits: Bool = false,
        onError: @escaping (String) -> Void
    ) {
        onMaterialRendered = {}
        materials = nil
        onMaterialError = { _ in }
        self.mesh = .expanded(mesh)
        self.isWireframe = isWireframe
        self.showsColor = showsColor
        self.automaticallyOrbits = automaticallyOrbits
        self.cameraReset = cameraReset
        self.cameraCommand = cameraCommand
        self.meshRevision = meshRevision
        self.onError = onError
    }

    /// Display indexed geometry with optional baked maps; existing SDK call sites retain their API.
    /// - Parameters:
    ///   - mesh: Immutable copied geometry.
    ///   - isWireframe: Draw triangle edges.
    ///   - automaticallyOrbits: Opt-in turntable, paused by Reduce Motion, visibility and direct manipulation.
    ///   - showsColor: Display source colors and materials; false uses neutral shading while preserving alpha policy.
    ///   - cameraReset: Increment to fit the model.
    ///   - cameraCommand: A discrete activation consumed once across viewport refreshes.
    ///   - meshRevision: Increment for replacement geometry/material output.
    ///   - bakedMesh: Current matching baked output, or nil for ordinary geometry.
    ///   - onMaterialError: Material failure retaining ordinary geometry; defaults to onError.
    ///   - onMaterialRendered: A current GPU frame completed successfully.
    ///   - onError: Ordinary GPU setup diagnostic.
    public init(
        mesh: IndexedMesh, isWireframe: Bool, cameraReset: Int, meshRevision: Int = 0,
        bakedMesh: MeshWithBakedTextures? = nil, cameraCommand: MeshCameraCommand? = nil, showsColor: Bool = true,
        automaticallyOrbits: Bool = false,
        onMaterialError: ((String) -> Void)? = nil,
        onMaterialRendered: @escaping () -> Void = {}, onError: @escaping (String) -> Void
    ) {
        self.init(
            mesh: mesh, isWireframe: isWireframe, cameraReset: cameraReset, meshRevision: meshRevision,
            materials: bakedMesh.map(MeshMaterialContent.baked), cameraCommand: cameraCommand, showsColor: showsColor,
            automaticallyOrbits: automaticallyOrbits,
            onMaterialError: onMaterialError,
            onMaterialRendered: onMaterialRendered, onError: onError)
    }

    /// Display one matching baked, source-baked or imported representation without replacing the orbit view.
    /// - Parameters:
    ///   - mesh: Immutable copied indexed geometry, retained as the failure fallback.
    ///   - isWireframe: Draw triangle edges.
    ///   - automaticallyOrbits: Opt-in turntable, paused by Reduce Motion, visibility and direct manipulation.
    ///   - showsColor: Display source colors and materials; false uses neutral shading while preserving alpha policy.
    ///   - cameraReset: Increment to fit the model.
    ///   - cameraCommand: A discrete activation consumed once across viewport refreshes.
    ///   - meshRevision: Increment for replacement geometry/material output or retry.
    ///   - materials: Mutually exclusive current material data; uploads off the main actor.
    ///   - onMaterialError: Original material preparation/GPU cause; defaults to onError.
    ///   - onMaterialRendered: Called only after a current material GPU frame completes.
    ///   - onError: Ordinary geometry setup failure on the main actor.
    public init(
        mesh: IndexedMesh, isWireframe: Bool, cameraReset: Int, meshRevision: Int = 0,
        materials: MeshMaterialContent?, cameraCommand: MeshCameraCommand? = nil, showsColor: Bool = true,
        automaticallyOrbits: Bool = false,
        onMaterialError: ((String) -> Void)? = nil,
        onMaterialRendered: @escaping () -> Void = {}, onError: @escaping (String) -> Void
    ) {
        self.onMaterialRendered = onMaterialRendered
        self.materials = materials
        self.onMaterialError = onMaterialError ?? onError
        self.mesh = .indexed(mesh)
        self.isWireframe = isWireframe
        self.showsColor = showsColor
        self.automaticallyOrbits = automaticallyOrbits
        self.cameraReset = cameraReset
        self.cameraCommand = cameraCommand
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
        updateRenderer(in: view, reduceMotion: context.environment.accessibilityReduceMotion)
    }
    public static func dismantleNSView(_ view: InteractiveMeshView, coordinator: ()) {
        view.automaticOrbitBinding.dismantle()
        view.cancelMaterialUpload()
        view.delegate = nil
    }

    // Direct renderer tests have no installed SwiftUI environment; production passes the context's current value.
    func updateRenderer(in view: InteractiveMeshView, reduceMotion: Bool = false) {
        defer { view.automaticOrbitBinding.update(requested: automaticallyOrbits, reduceMotion: reduceMotion) }
        if materials == nil || view.meshRevision != meshRevision {
            view.cancelMaterialUpload()
            view.materialRenderer = nil
            view.importedRenderer = nil
            view.colorPixelFormat = .bgra8Unorm
            view.delegate = view.renderer
        }
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
            view.automaticOrbitBinding.cameraInputChanged()
        }
        if let cameraCommand { view.applyCameraCommand(cameraCommand) }
        view.renderer?.showsColor = showsColor
        view.materialRenderer?.showsColor = showsColor
        view.importedRenderer?.showsColor = showsColor
        view.requestedShowsColor = showsColor
        view.renderer?.isWireframe = isWireframe
        view.materialRenderer?.isWireframe = isWireframe
        view.importedRenderer?.isWireframe = isWireframe
        view.requestedWireframe = isWireframe
        switch materials {
        case .baked(let baked):
            view.updateMaterials(
                baked, revision: meshRevision, onRendered: onMaterialRendered, onError: onMaterialError)
        case .sourceBaked(let baked):
            view.updateSourceMaterials(
                baked, revision: meshRevision, onRendered: onMaterialRendered, onError: onMaterialError)
        case .imported(let imported):
            view.updateImportedMaterials(
                imported, revision: meshRevision, onRendered: onMaterialRendered, onError: onMaterialError)
        case nil: break
        }
        view.needsDisplay = true
    }
}

@MainActor
/// AppKit event boundary owned by MeshViewport; geometry and camera remain renderer-owned.
public class InteractiveMeshView: MTKView {
    var renderer: MeshRenderer?
    var materialRenderer: TexturedMeshRenderer?
    var importedRenderer: ImportedMeshRenderer?
    var materialTask: Task<Void, Never>?
    var requestedMaterialRevision: Int?
    var completedMaterialRevision: Int?
    var failedMaterialRevision: Int?
    var requestedWireframe = false
    var requestedShowsColor = true
    let materialBuilder = TexturedMetalResourcesBuilder()
    let importedMaterialBuilder = ImportedMetalResourcesBuilder()

    lazy var automaticOrbitBinding = AutomaticOrbitViewBinding(view: self)

    private var fallbackCamera = OrbitCamera()
    private var lastCameraCommand: UUID?

    func applyCameraCommand(_ command: MeshCameraCommand) {
        guard lastCameraCommand != command.id else { return }
        lastCameraCommand = command.id
        automaticOrbitBinding.cameraInputChanged()
        switch command.action {
        case .orbitLeft: orbitCamera.orbit(horizontal: -18, vertical: 0)
        case .orbitRight: orbitCamera.orbit(horizontal: 18, vertical: 0)
        case .orbitUp: orbitCamera.orbit(horizontal: 0, vertical: -18)
        case .orbitDown: orbitCamera.orbit(horizontal: 0, vertical: 18)
        case .panLeft: orbitCamera.pan(horizontal: -0.16, vertical: 0)
        case .panRight: orbitCamera.pan(horizontal: 0.16, vertical: 0)
        case .panUp: orbitCamera.pan(horizontal: 0, vertical: 0.16)
        case .panDown: orbitCamera.pan(horizontal: 0, vertical: -0.16)
        case .zoomIn: orbitCamera.zoom(delta: 6)
        case .zoomOut: orbitCamera.zoom(delta: -6)
        }
        needsDisplay = true
    }

    var orbitCamera: OrbitCamera {
        get { importedRenderer?.camera ?? materialRenderer?.camera ?? renderer?.camera ?? fallbackCamera }
        set {
            fallbackCamera = newValue
            renderer?.camera = newValue
            materialRenderer?.camera = newValue
            importedRenderer?.camera = newValue
        }
    }

    func cancelMaterialUpload() {
        materialTask?.cancel()
        materialTask = nil
        requestedMaterialRevision = nil
        completedMaterialRevision = nil
        failedMaterialRevision = nil
    }

    func updateMaterials(
        _ baked: MeshWithBakedTextures, revision: Int, onRendered: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        updateTexturedMaterials(.legacy(baked), revision: revision, onRendered: onRendered, onError: onError)
    }

    func updateSourceMaterials(
        _ baked: SourceBakedMesh, revision: Int, onRendered: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        updateTexturedMaterials(.source(baked), revision: revision, onRendered: onRendered, onError: onError)
    }

    private func updateTexturedMaterials(
        _ input: TexturedMaterialInput, revision: Int, onRendered: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
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
                let resources = try await builder.make(input: input, device: device, camera: camera)
                try Task.checkCancellation()
                guard let self, self.requestedMaterialRevision == revision, self.meshRevision == revision else {
                    return
                }
                let renderer = TexturedMeshRenderer(resources: resources)
                renderer.camera = self.orbitCamera
                renderer.isWireframe = self.requestedWireframe
                renderer.showsColor = self.requestedShowsColor
                renderer.onError = { [weak self] error in
                    guard let self, self.completedMaterialRevision == revision else { return }
                    onError(error.localizedDescription)
                }
                renderer.onRendered = { [weak self, weak renderer] in
                    guard let self, let renderer, self.completedMaterialRevision == revision,
                        self.materialRenderer === renderer, self.delegate === renderer
                    else { return }
                    onRendered()
                }
                self.importedRenderer = nil
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

    func updateImportedMaterials(
        _ imported: ImportedMaterialRenderData, revision: Int, onRendered: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard requestedMaterialRevision != revision, completedMaterialRevision != revision,
            failedMaterialRevision != revision
        else { return }
        materialTask?.cancel()
        requestedMaterialRevision = revision
        let camera = orbitCamera
        let builder = importedMaterialBuilder
        let device = device
        materialTask = Task { [weak self] in
            do {
                guard let device else {
                    throw ImportedRenderError.unavailable("This Mac does not provide a Metal device.")
                }
                let resources = try await builder.make(data: imported, device: device, camera: camera)
                try Task.checkCancellation()
                guard let self, self.requestedMaterialRevision == revision, self.meshRevision == revision else {
                    return
                }
                let renderer = ImportedMeshRenderer(resources: resources)
                renderer.camera = self.orbitCamera
                renderer.isWireframe = self.requestedWireframe
                renderer.showsColor = self.requestedShowsColor
                renderer.onError = { [weak self] error in
                    guard let self, self.completedMaterialRevision == revision else { return }
                    onError(error.localizedDescription)
                }
                renderer.onRendered = { [weak self, weak renderer] in
                    guard let self, let renderer, self.completedMaterialRevision == revision,
                        self.importedRenderer === renderer, self.delegate === renderer
                    else { return }
                    onRendered()
                }
                self.materialRenderer = nil
                self.importedRenderer = renderer
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
    var isDraggingCamera: Bool { lastDragLocation != nil }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        automaticOrbitBinding.movedToWindow()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        automaticOrbitBinding.visibilityChanged()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        automaticOrbitBinding.visibilityChanged()
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragLocation = event.locationInWindow
        automaticOrbitBinding.cameraInputChanged()
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
        automaticOrbitBinding.cameraInputChanged()
    }

    public override func scrollWheel(with event: NSEvent) {
        automaticOrbitBinding.cameraInputChanged()
        orbitCamera.zoom(delta: Float(event.scrollingDeltaY))
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
        automaticOrbitBinding.cameraInputChanged()
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
