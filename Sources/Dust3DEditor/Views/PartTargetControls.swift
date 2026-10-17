import Dust3DDocument
import SwiftUI

struct PartTargetControls: View {
    let store: EditorStore
    let part: DocumentPart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Part role").font(.headline)
            Picker(
                "Part role",
                selection: Binding<PartTarget?>(
                    get: { part.target }, set: { if let target = $0 { store.setPartTarget(part.id, target: target) } }
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
            Text(
                "Profiles supply cross-sections without joining the mesh. Stitching roles supply component boundaries; stitching settings are separate. Each choice is one undo step."
            )
            .font(.caption).foregroundStyle(.primary)
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
