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
        } label: {
            Label("Export", systemImage: "square.and.arrow.up").frame(minHeight: 40)
        }
        .disabled(!canExport)
        .help("Export original procedural geometry as OBJ or FBX")
        .accessibilityLabel("Export original procedural geometry")
    }
}
