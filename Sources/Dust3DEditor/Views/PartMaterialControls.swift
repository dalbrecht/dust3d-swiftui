import Dust3DDocument
import SwiftUI

struct PartMaterialControls: View {
    let store: EditorStore
    let part: DocumentPart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Material").font(.headline)
            ForEach(PartMaterialProperty.allCases, id: \.self) { property in
                PartMaterialScalarControl(store: store, part: part, property: property)
            }
            Text(
                "Values are saved in the document. This preview does not yet display metallic, roughness or glow effects."
            )
            .font(.caption).foregroundStyle(.primary)
        }
    }
}

private struct PartMaterialScalarControl: View {
    let store: EditorStore
    let part: DocumentPart
    let property: PartMaterialProperty
    @State private var draft = ""

    private var title: String {
        switch property {
        case .metallic: "Metallic"
        case .roughness: "Roughness"
        case .emissive: "Glow"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextField(title, text: $draft)
                .monospacedDigit()
                .frame(minHeight: 40)
                .accessibilityIdentifier("part-material-\(property.rawValue)")
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { apply() }
                .onExitCommand { reset() }
            if part.materialValue(property) == nil {
                Text("Unsupported source value. Apply a value to replace it.")
                    .font(.caption).foregroundStyle(.primary)
            }
            Text("0–\(Int(property.bounds.upperBound)); default \(Int(property.defaultValue))")
                .font(.caption).foregroundStyle(.primary).monospacedDigit()
            HStack {
                Button(action: reset) { Text("Reset Draft").frame(minHeight: 32) }
                    .accessibilityLabel("Reset \(title.lowercased()) draft")
                Spacer()
                Button(action: apply) { Text("Apply").frame(minHeight: 32) }
                    .accessibilityLabel("Apply \(title.lowercased())")
            }
        }
        .onChange(of: part.id, initial: true) { _, _ in reset() }
        .onChange(of: part.materialValue(property)) { _, _ in reset() }
    }

    private func reset() { draft = part.materialValue(property).map { String($0) } ?? "" }
    private func apply() { store.setPartMaterial(part.id, property: property, value: draft) }
}
