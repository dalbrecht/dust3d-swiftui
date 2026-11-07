import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct PartMirrorControls: View {
    let store: EditorStore
    var graphTarget: GraphModelPartTarget? = nil

    var body: some View {
        if let graphTarget {
            if let part = graphTarget.part {
                editor(for: part, target: PartMirrorTarget(graphTarget: graphTarget))
            }
        } else if let snapshot = store.snapshot, let part = snapshot.mirrorInspectorPart {
            editor(for: part, target: PartMirrorTarget(snapshot: snapshot, partID: part.id))
        }
    }

    private func editor(for part: DocumentPart, target: PartMirrorTarget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let value = part.xMirrored {
                Toggle(
                    "Mirrored", isOn: Binding(get: { value }, set: { store.partMirrorAction($0, target: target)() })
                )
                .accessibilityIdentifier("part-x-mirrored")
            } else {
                Text("Mirrored: Unsupported source value").font(.caption)
                HStack {
                    Button("Set Mirrored On", action: store.partMirrorAction(true, target: target))
                    Button("Set Mirrored Off", action: store.partMirrorAction(false, target: target))
                }
            }
            Text("Adds a reflected copy across the YZ plane through the canvas origin. Authored nodes stay in place.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!store.canEditPartMirror(target))
    }
}
