import Dust3DRendering
import SwiftUI

struct PreviewCameraMenu: View {
    let title: String
    let isEnabled: Bool
    let allowsZoomShortcuts: Bool
    let move: (MeshCameraCommand.Action) -> Void
    let fit: () -> Void
    var canvasWheelZoom: Binding<Bool>? = nil
    var canZoomFromCanvas = false

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
                    .keyboardShortcut(allowsZoomShortcuts ? KeyboardShortcut("=", modifiers: .option) : nil)
                Button("Zoom Out") { move(.zoomOut) }
                    .keyboardShortcut(allowsZoomShortcuts ? KeyboardShortcut("-", modifiers: .option) : nil)
                Button("Fit Mesh", action: fit)
            }.disabled(!isEnabled)
            if let canvasWheelZoom {
                Divider()
                Toggle("Scroll Blank Canvas to Zoom", isOn: canvasWheelZoom)
                    .disabled(!canZoomFromCanvas)
                    .help("Zoom the visible mesh by scrolling over blank space in the active editing profile.")
            }
        }
    }
}
