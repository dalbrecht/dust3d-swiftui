import Dust3DRendering
import SwiftUI

struct PreviewCameraMenu: View {
    let title: String
    let isEnabled: Bool
    let move: (MeshCameraCommand.Action) -> Void
    let fit: () -> Void

    var body: some View {
        Menu(title) {
            Group {
                Button("Orbit Left") { move(.orbitLeft) }
                Button("Orbit Right") { move(.orbitRight) }
                Button("Orbit Up") { move(.orbitUp) }
                Button("Orbit Down") { move(.orbitDown) }
                Divider()
                Button("Pan Left") { move(.panLeft) }
                Button("Pan Right") { move(.panRight) }
                Button("Pan Up") { move(.panUp) }
                Button("Pan Down") { move(.panDown) }
                Divider()
                Button("Zoom In") { move(.zoomIn) }
                Button("Zoom Out") { move(.zoomOut) }
                Button("Fit Mesh", action: fit)
            }.disabled(!isEnabled)
        }
    }
}
