import Dust3DKit
import SwiftUI

/// One window-owned export menu; the workflow remains authoritative for busy/source admission.
struct EditorGeometryExportMenu: View {
    let canExport: Bool
    let onExport: (DocumentExportFormat) -> Void

    var body: some View {
        Menu {
            Button("OBJ Geometry…") { onExport(.obj) }
            Button("FBX Geometry…") { onExport(.fbx) }
            Button("Textured FBX…") { onExport(.fbxTextured) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up").frame(minHeight: 40)
        }
        .disabled(!canExport)
        .help("Export geometry or textured FBX")
        .accessibilityLabel("Export model")
    }
}
