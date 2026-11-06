import Foundation
import Observation

/// Camera ownership for one logical viewport across replacement SwiftUI surfaces.
/// Keep this object with the preview session. Public controls invalidate the view;
/// direct pointer input updates the camera without rebuilding surrounding UI.
@MainActor @Observable
public final class MeshCameraState {
    public private(set) var revision = 0
    /// Input lease invalidates pending picks without rebuilding observation-driven UI.
    @ObservationIgnored package private(set) var inputRevision = UUID()
    @ObservationIgnored private(set) var camera = OrbitCamera()
    @ObservationIgnored private let interactionAllowed: @MainActor () -> Bool

    /// Create an independent camera. The gate applies only to direct viewport input;
    /// callers validate their own session epoch before invoking move or fit.
    /// - Parameter interactionAllowed: Whether pointer, keyboard and turntable input
    ///   may replace this camera. Defaults to allowing interaction.
    public init(interactionAllowed: @escaping @MainActor () -> Bool = { true }) {
        self.interactionAllowed = interactionAllowed
    }

    /// Perform one discrete camera control. Construction or remounting never replays it.
    /// - Parameter action: Orbit, screen-space pan or bounded zoom movement.
    public func move(_ action: MeshCameraCommand.Action) {
        switch action {
        case .orbitLeft: camera.orbit(horizontal: -18, vertical: 0)
        case .orbitRight: camera.orbit(horizontal: 18, vertical: 0)
        case .orbitUp: camera.orbit(horizontal: 0, vertical: -18)
        case .orbitDown: camera.orbit(horizontal: 0, vertical: 18)
        case .panLeft: camera.pan(horizontal: -0.16, vertical: 0)
        case .panRight: camera.pan(horizontal: 0.16, vertical: 0)
        case .panUp: camera.pan(horizontal: 0, vertical: 0.16)
        case .panDown: camera.pan(horizontal: 0, vertical: -0.16)
        case .zoomIn: camera.zoom(delta: 6)
        case .zoomOut: camera.zoom(delta: -6)
        }
        inputRevision = UUID()
        revision += 1
    }

    /// Fit this logical viewport. Programmatic reset remains possible while the
    /// interaction gate is closed during a source transition.
    public func fit() {
        camera = OrbitCamera()
        inputRevision = UUID()
        revision += 1
    }

    /// Resize or backing changes invalidate projection-dependent picks without moving the camera.
    package func invalidateProjection(interactionAllowed: @MainActor () -> Bool = { true }) {
        guard interactionAllowed() else { return }
        inputRevision = UUID()
    }

    /// Raw input is drawn by its existing view and must not invalidate SwiftUI.
    /// The origin gate belongs to that mounted view's source/presentation epoch;
    /// current owner readiness alone cannot admit input from an obsolete view.
    func replaceFromInteraction(
        _ camera: OrbitCamera, interactionAllowed: @MainActor () -> Bool = { true }
    ) -> Bool {
        guard interactionAllowed(), self.interactionAllowed() else { return false }
        self.camera = camera
        inputRevision = UUID()
        return true
    }
}
