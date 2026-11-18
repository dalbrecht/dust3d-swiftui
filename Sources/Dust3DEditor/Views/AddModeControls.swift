import SwiftUI

struct AddModeControls: View {
    let store: EditorStore
    var body: some View {
        let modeID = store.addModeID
        let toggleAction = store.addPlacementToggleAction()
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Add Nodes with Pointer",
                isOn: Binding(
                    get: { store.isAddingNodes },
                    set: { active in toggleAction(active) })
            )
            .disabled(!store.isAddingNodes && !store.canBeginAddMode)
            .help("While the canvas has keyboard focus, A toggles Add and S returns to selection.")
            if store.isAddingNodes {
                Text(
                    store.addPlacement.anchorID == nil
                        ? "Move the pointer, then press to start a new part."
                        : "Move the pointer, then press to extend or connect the anchor."
                )
                .font(.caption)
                Text(
                    "Preview radius: \(store.addGhostModelRadius.formatted(.number.precision(.fractionLength(0...4)))) document units"
                )
                .font(.caption).monospacedDigit()
                if let limit = store.addRadiusLimitNotice {
                    Text(limit).font(.caption).foregroundStyle(.secondary).accessibilityLabel(limit)
                }
                if let notice = store.addPlacementNotice {
                    Text("Connection unavailable: \(notice)").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Connection fallback: \(notice)")
                }
                Button("Preview at Canvas Center") { store.previewAddAtCanvasCenter() }
                    .disabled(store.isWorking || store.frozenAddProjection == nil)
                HStack {
                    Button("Left") { store.nudgeAddPreview(x: -16, y: 0) }
                    Button("Right") { store.nudgeAddPreview(x: 16, y: 0) }
                    Button("Up") { store.nudgeAddPreview(x: 0, y: -16) }
                    Button("Down") { store.nudgeAddPreview(x: 0, y: 16) }
                }.disabled(store.addGhostPoint == nil || store.isWorking)
                HStack {
                    Button("Smaller Preview") { store.adjustSelectionRadius(direction: -1) }
                    Button("Larger Preview") { store.adjustSelectionRadius(direction: 1) }
                }.disabled(store.addGhostPoint == nil || store.isWorking)
                Button("Place Preview Node") {
                    if let point = store.addGhostPoint { store.placeAddNode(at: point, modeID: modeID) }
                }.disabled(!store.canPlaceAddGhost)
                if store.addAnchorIsReadOnly {
                    Label("The anchor is read-only.", systemImage: "lock").font(.caption)
                }
                Button("Cancel Add Mode") { store.cancelAddMode() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pointer node placement")
    }
}
