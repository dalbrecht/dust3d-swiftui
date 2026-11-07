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
            .help("With a graph selection in Side by Side, press E while the canvas has focus to switch profiles.")
            let setRigEdgeSelection = store.rigEdgeSelectionToggleAction()
            Toggle(
                "Select Edges for Bone Assignment",
                isOn: Binding(get: { store.isSelectingRigEdges }, set: setRigEdgeSelection)
            )
            .disabled(!store.canChangeRigEdgeSelection)
            .help("Pick edges in the canvas, then choose a template bone and assign the selected edges.")
        }
    }
}

struct CanvasProfilePanes: View {
    let store: EditorStore
    @State private var requestedFocus: (lease: UUID, request: CanvasProfileFocusRequest)?

    var body: some View {
        if store.canvasProfiles.isDualProfile {
            GeometryReader { geometry in
                let dividerWidth = 1.0
                let paneWidth = CanvasProfileWorkspace.paneWidth(
                    totalWidth: geometry.size.width, dividerWidth: dividerWidth)
                let planes = store.canvasProfiles.visiblePlanes
                let lease = store.canvasProfiles.lease
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
                                    ZStack {
                                        CanvasProfileCompanion(store: store, plane: plane)
                                        CanvasProfileActivationSurface { request in
                                            if let activeLease = store.activateCanvasCompanion(
                                                plane: plane, expectedLease: lease)
                                            {
                                                requestedFocus = (activeLease, request)
                                            }
                                        }
                                        .accessibilityHidden(true)
                                        .help("Click to edit \(plane.rawValue)")
                                    }
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
        let lease = store.canvasProfiles.lease
        let switchProfile: ((CanvasProfileFocusRequest) -> Bool)? =
            store.canSwitchSelectedCanvasProfile
            ? { request in
                guard let activeLease = store.switchSelectedCanvasProfile(expectedLease: lease) else { return false }
                requestedFocus = (activeLease, request)
                return true
            } : nil
        return NodeCanvas(
            store: store, profileLease: lease,
            profileFocusRequest: requestedFocus?.lease == lease ? requestedFocus?.request : nil,
            switchProfile: switchProfile
        )
        .id(lease)
    }
}
