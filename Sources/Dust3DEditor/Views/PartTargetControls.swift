import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct PartTargetControls: View {
    let store: EditorStore
    let part: DocumentPart
    var graphTarget: GraphPartRoleTarget? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Part role").font(.headline)
            Picker(
                "Part role",
                selection: Binding<PartTarget?>(
                    get: { part.target }, set: { apply($0) }
                )
            ) {
                if part.target == nil {
                    Text("Unsupported source role").tag(nil as PartTarget?).disabled(true)
                }
                ForEach(PartTarget.allCases, id: \.self) { target in
                    Text(title(target)).tag(Optional(target))
                }
            }
            .labelsHidden().pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Part role")
            .accessibilityIdentifier("part-target")
            if part.target == .cutFace {
                CutFaceReferenceCountLabel(count: part.cutFaceReferenceCount)
            }
            Text(
                "Profiles supply cross-sections without joining the mesh. Stitching roles supply component boundaries; stitching settings are separate. Each choice is one undo step."
            )
            .font(.caption).foregroundStyle(.primary)
        }
    }

    private func apply(_ role: PartTarget?) {
        guard let role else { return }
        if let graphTarget {
            store.setGraphPartRole(role, target: graphTarget)
        } else {
            store.setPartTarget(part.id, target: role)
        }
    }

    private func title(_ target: PartTarget) -> String {
        switch target {
        case .model: return "Model"
        case .cutFace: return "Cross-section profile"
        case .stitchingLine: return "Stitching line"
        case .stitchingLoop: return "Stitching loop"
        }
    }
}

struct CutFaceReferenceCountLabel: View {
    let count: Int

    var body: some View {
        LabeledContent("Linked references", value: count.formatted())
            .font(.caption)
            .accessibilityIdentifier("cut-face-reference-count")
    }
}
