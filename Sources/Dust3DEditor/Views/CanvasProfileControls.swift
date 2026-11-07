import AppKit
import Dust3DEditorModel
import SwiftUI

struct CanvasProfileHeader: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Node canvas").font(.headline)
                Spacer()
                Toggle(
                    "Side by Side",
                    isOn: Binding(
                        get: { store.canvasProfiles.isDualProfile },
                        set: { store.setDualCanvasProfile($0) })
                )
                .toggleStyle(.button)
                .help("Show both profiles. Use the Editing Profile picker to choose where to edit.")
            }
            Picker("Editing Profile", selection: $store.plane) {
                ForEach(EditingPlane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }
}

struct CanvasProfilePanes: View {
    let store: EditorStore

    var body: some View {
        if store.canvasProfiles.isDualProfile {
            GeometryReader { geometry in
                let dividerWidth = 1.0
                let paneWidth = CanvasProfileWorkspace.paneWidth(
                    totalWidth: geometry.size.width, dividerWidth: dividerWidth)
                let planes = store.canvasProfiles.visiblePlanes
                VStack(spacing: 0) {
                    HStack(spacing: dividerWidth) {
                        ForEach(planes, id: \.self) { plane in
                            Group {
                                if plane == store.plane {
                                    Text("\(plane.rawValue) · Editing")
                                        .accessibilityAddTraits(.isHeader)
                                } else {
                                    Button("Edit \(plane.rawValue)") { store.plane = plane }
                                        .buttonStyle(.link)
                                }
                            }
                            .font(.caption)
                            .padding(6)
                            .frame(width: paneWidth)
                        }
                    }
                    Divider()
                    HStack(spacing: dividerWidth) {
                        ForEach(planes, id: \.self) { plane in
                            Group {
                                if plane == store.plane {
                                    editingCanvas
                                } else {
                                    CanvasProfileCompanion(store: store, plane: plane)
                                }
                            }
                            .frame(width: paneWidth)
                        }
                    }
                }
                .overlay {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: dividerWidth)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        } else {
            editingCanvas
        }
    }

    private var editingCanvas: some View {
        NodeCanvas(store: store, profileLease: store.canvasProfiles.lease)
            .id(store.canvasProfiles.lease)
    }
}
