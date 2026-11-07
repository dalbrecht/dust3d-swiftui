import Dust3DEditorModel
import Foundation

/// Tracks which projection owns canvas input across pane and layout changes.
struct CanvasProfileWorkspace {
    private(set) var activePlane = EditingPlane.front
    private(set) var isDualProfile = false
    private(set) var lease = UUID()

    var visiblePlanes: [EditingPlane] {
        isDualProfile ? EditingPlane.allCases : [activePlane]
    }

    mutating func activate(_ plane: EditingPlane) {
        guard activePlane != plane else { return }
        activePlane = plane
        lease = UUID()
    }

    mutating func setDualProfile(_ enabled: Bool) {
        guard isDualProfile != enabled else { return }
        isDualProfile = enabled
        lease = UUID()
    }

    mutating func retireLease() {
        lease = UUID()
    }

    func owns(_ candidate: UUID) -> Bool {
        lease == candidate
    }
}
