import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct PartCutFaceControls: View {
    let store: EditorStore
    let part: DocumentPart
    @State private var rotation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cross-section profile").font(.headline)
            Picker(
                "Cut-face preset",
                selection: Binding<CutFaceSelection?>(
                    get: { part.cutFace },
                    set: { if let value = $0 { store.setPartCutFace(part.id, selection: value) } }
                )
            ) {
                ForEach(PartCutFaceOptions.selections(current: part.cutFace), id: \.self) { selection in
                    Text(title(selection)).tag(selection).disabled(selection == nil)
                }
            }
            .labelsHidden().pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Cut-face preset")
            .accessibilityIdentifier("part-cut-face")
            if case .linkedPart(let id) = part.cutFace {
                Text(store.snapshot?.parts.first(where: { $0.id == id })?.title ?? "Unresolved profile")
                    .font(.callout)
                Text(id).font(.caption).textSelection(.enabled)
                    .focusedValue(\.editorTextEditing, true)
            }
            DisclosureGroup("Link profile…") {
                PartProfileChooser(store: store, part: part)
            }
            Text("Rotation (half-turns)").font(.callout)
            TextField("Rotation (half-turns)", text: $rotation)
                .accessibilityIdentifier("part-cut-rotation")
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { applyRotation() }
            if part.cutRotation == nil {
                Text("Unsupported source rotation. Enter a value to replace it.")
                    .font(.caption).foregroundStyle(.primary)
            }
            HStack {
                Button("Reset Draft") { resetRotation() }
                    .accessibilityLabel("Reset cut-face rotation draft")
                Spacer()
                Button("Apply") { applyRotation() }
                    .accessibilityLabel("Apply cut-face rotation")
            }
            Text("Rotation ranges from −1 to 1; 1 is 180°. Each profile choice or applied rotation is one undo step.")
                .font(.caption).foregroundStyle(.primary)
        }
        .onChange(of: part.id, initial: true) { _, _ in resetRotation() }
        .onChange(of: part.cutRotation) { _, _ in resetRotation() }
    }

    private func title(_ selection: CutFaceSelection?) -> String {
        switch selection {
        case .preset(let preset): return preset.rawValue
        case .linkedPart: return "Linked profile"
        case nil: return "Unsupported source value"
        }
    }

    private func resetRotation() { rotation = part.cutRotation.map { String($0) } ?? "" }
    private func applyRotation() { store.setPartCutRotation(part.id, rotation: rotation) }
}
