import Dust3DEditorModel
import SwiftUI

/// Both menu and inspector buttons capture their rendered source and membership.
struct CanvasPartIsolationButtons: View {
    let store: EditorStore?
    let componentID: String?
    let partID: String?

    init(store: EditorStore?, componentID: String? = nil, partID: String? = nil) {
        self.store = store
        self.componentID = componentID
        self.partID = partID
    }

    var body: some View {
        let target = store?.snapshot.map {
            CanvasPartIsolationTarget(snapshot: $0, componentID: componentID, partID: partID)
        }
        let showAll = store?.snapshot.map { CanvasPartIsolationTarget(snapshot: $0, showAll: true) }
        Button(target?.title ?? "Hide Other Parts in Canvas", action: store?.canvasPartIsolationAction(target) ?? {})
            .disabled(store?.canPerformCanvasPartIsolation(target) != true)
            .help(
                target?.unavailableReason ?? "Hide outside parts, or show all parts when the outside is already hidden."
            )
        if target?.restoresAll != true {
            Button("Show All Parts in Canvas", action: store?.canvasPartIsolationAction(showAll) ?? {})
                .disabled(store?.canPerformCanvasPartIsolation(showAll) != true)
                .help(showAll?.unavailableReason ?? "Restore canvas visibility for every part.")
        }
    }
}

struct CanvasPartIsolationControls: View {
    let store: EditorStore
    var componentID: String?
    var partID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CanvasPartIsolationButtons(store: store, componentID: componentID, partID: partID)
            Text("Canvas visibility affects editing overlays. Each change is one Undo step.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
