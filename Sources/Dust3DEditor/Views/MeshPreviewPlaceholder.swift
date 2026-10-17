import SwiftUI

struct MeshPreviewPlaceholder: View {
    let message: String?

    var body: some View {
        ContentUnavailableView {
            Label("Mesh preview", systemImage: "cube.transparent")
        } description: {
            Text(message ?? "Open a .ds3 model to begin editing.").foregroundStyle(.primary)
        }
    }
}
