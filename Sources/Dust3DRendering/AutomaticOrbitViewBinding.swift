import AppKit

/// Observes only this viewport's window; SwiftUI retains ownership of the user's rotation preference.
@MainActor
final class AutomaticOrbitViewBinding: NSObject {
    private weak var view: InteractiveMeshView?
    private var requested = false
    private var reduceMotion = false
    private lazy var driver = AutomaticOrbitDriver(
        canAnimate: { [weak self] in self?.availability.canAnimate == true },
        advance: { [weak self] delta in
            guard let view = self?.view else { return }
            var camera = view.orbitCamera
            camera.yaw = (camera.yaw + delta).truncatingRemainder(dividingBy: 2 * .pi)
            view.orbitCamera = camera
            view.needsDisplay = true
        })

    init(view: InteractiveMeshView) { self.view = view }

    private var availability: AutomaticOrbitAvailability {
        let window = view?.window
        return AutomaticOrbitAvailability(
            requested: requested, reduceMotion: reduceMotion, hasWindow: window != nil,
            isVisible: window?.isVisible == true && window?.isMiniaturized == false
                && window?.occlusionState.contains(.visible) == true && view?.isHiddenOrHasHiddenAncestor == false,
            isKeyWindow: window?.isKeyWindow == true, isAppActive: NSApp?.isActive == true,
            hasRenderer: view?.renderer != nil && view?.failedMeshRevision == nil,
            isDragging: view?.isDraggingCamera == true)
    }

    func update(requested: Bool, reduceMotion: Bool) {
        self.requested = requested
        self.reduceMotion = reduceMotion
        driver.reconcile()
    }

    func movedToWindow() {
        NotificationCenter.default.removeObserver(self)
        if let window = view?.window {
            for name in [
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                NSWindow.didChangeOcclusionStateNotification,
            ] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(availabilityDidChange(_:)), name: name, object: window)
            }
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(availabilityDidChange(_:)), name: name, object: NSApp)
            }
        }
        driver.reconcile()
    }

    func visibilityChanged() { driver.reconcile() }

    func cameraInputChanged() {
        driver.resetTiming()
        driver.reconcile()
    }

    func dismantle() {
        requested = false
        driver.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func availabilityDidChange(_ notification: Notification) { driver.reconcile() }

    deinit { NotificationCenter.default.removeObserver(self) }
}
