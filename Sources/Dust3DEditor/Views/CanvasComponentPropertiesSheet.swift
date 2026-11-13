import Dust3DEditorModel
import Foundation
import SwiftUI

/// A sheet keeps the owners from its opening gesture even when the pointer leaves the canvas.
struct CanvasComponentProperties: Identifiable {
    let id = UUID()
    private let documentIdentity: UUID
    private let selectionRevision: Int
    private let hovered: PartGraphTarget?
    private let componentIDs: [Data]

    init?(snapshot: EditorSnapshot, hovered: PartGraphTarget?) {
        let target = ComponentMeshSelectionTarget(graphSelection: snapshot, hovered: hovered)
        guard target.isCurrent(in: snapshot) else { return nil }
        documentIdentity = snapshot.documentIdentity
        selectionRevision = snapshot.selectionRevision
        self.hovered = hovered
        componentIDs = target.ids.map { Data($0.utf8) }
    }

    func target(in snapshot: EditorSnapshot) -> ComponentMeshSelectionTarget? {
        guard documentIdentity == snapshot.documentIdentity, selectionRevision == snapshot.selectionRevision else {
            return nil
        }
        let target = ComponentMeshSelectionTarget(graphSelection: snapshot, hovered: hovered)
        return target.ids.map { Data($0.utf8) } == componentIDs ? target : nil
    }
}

struct CanvasComponentPropertiesSheet: View {
    let store: EditorStore
    let properties: CanvasComponentProperties
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Component Properties").font(.title2).accessibilityAddTraits(.isHeader)
            if let snapshot = store.snapshot, let target = properties.target(in: snapshot) {
                ScrollView {
                    ComponentMeshSelectionControls(store: store).graphEditor(snapshot: snapshot, target: target)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Components Changed", systemImage: "square.3.layers.3d")
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }
}
