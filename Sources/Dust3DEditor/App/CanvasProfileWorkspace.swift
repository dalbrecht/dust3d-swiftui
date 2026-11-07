import Dust3DEditorModel
import Foundation

/// Tracks which projection owns canvas input across pane and layout changes.
struct CanvasProfileWorkspace {
    private(set) var activePlane = EditingPlane.front
    private(set) var isDualProfile = false
    private(set) var lease = UUID()
    private var suppressesContinuation = false

    var visiblePlanes: [EditingPlane] {
        isDualProfile ? EditingPlane.allCases : [activePlane]
    }

    static func paneWidth(totalWidth: Double, dividerWidth: Double) -> Double {
        guard totalWidth.isFinite, dividerWidth.isFinite, totalWidth >= 0, dividerWidth >= 0 else { return 0 }
        return max(0, (totalWidth - dividerWidth) / 2)
    }

    mutating func activate(_ plane: EditingPlane) {
        guard activePlane != plane else { return }
        activePlane = plane
        retireLease()
    }

    mutating func setDualProfile(_ enabled: Bool) {
        guard isDualProfile != enabled else { return }
        isDualProfile = enabled
        retireLease()
    }

    mutating func retireLease() {
        lease = UUID()
        suppressesContinuation = false
    }

    mutating func markActivationClick() {
        suppressesContinuation = true
    }

    mutating func admitsPrimaryPress(clickCount: Int, lease: UUID) -> Bool {
        guard owns(lease), clickCount > 0 else { return false }
        if clickCount == 1 { suppressesContinuation = false }
        return !suppressesContinuation
    }

    func owns(_ candidate: UUID) -> Bool {
        lease == candidate
    }
}
