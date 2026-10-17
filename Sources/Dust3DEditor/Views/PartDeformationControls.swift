import Dust3DDocument
import SwiftUI

struct PartDeformationControls: View {
    let store: EditorStore
    let part: DocumentPart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cross-section deformation").font(.headline)
            ForEach(PartDeformationProperty.allCases, id: \.self) { property in
                PartDeformationScaleControl(store: store, part: part, property: property)
            }
            if let value = part.isDeformationUnified {
                Toggle(
                    "Unified deformation",
                    isOn: Binding(
                        get: { value }, set: { store.setPartDeformationUnified(part.id, value: $0) })
                )
                .accessibilityIdentifier("part-deformation-unified")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unified deformation").font(.callout)
                    Picker(
                        "Unified deformation",
                        selection: Binding<Bool?>(
                            get: { nil },
                            set: {
                                if let value = $0 { store.setPartDeformationUnified(part.id, value: value) }
                            })
                    ) {
                        Text("Unsupported source value").tag(nil as Bool?)
                        Text("On").tag(Optional(true))
                        Text("Off").tag(Optional(false))
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Unified deformation")
                    .accessibilityIdentifier("part-deformation-unified")
                }
            }
            Text(
                "Scales range from 0 to 2; 1 preserves the original cross-section. Each applied change is one undo step."
            )
            .font(.caption).foregroundStyle(.primary)
        }
    }
}

private struct PartDeformationScaleControl: View {
    let store: EditorStore
    let part: DocumentPart
    let property: PartDeformationProperty
    @State private var draft = ""

    private var title: String { property == .width ? "Width scale" : "Thickness scale" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextField(title, text: $draft)
                .accessibilityIdentifier("part-deformation-\(property.rawValue)")
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { apply() }
            if part.deformationScale(property) == nil {
                Text("Unsupported source value. Enter a scale to replace it.")
                    .font(.caption).foregroundStyle(.primary)
            }
            HStack {
                Button("Reset Draft") { reset() }
                    .accessibilityLabel("Reset \(title.lowercased()) draft")
                Spacer()
                Button("Apply") { apply() }
                    .accessibilityLabel("Apply \(title.lowercased())")
            }
        }
        .onChange(of: part.id, initial: true) { _, _ in reset() }
        .onChange(of: part.deformationScale(property)) { _, _ in reset() }
    }

    private func reset() { draft = part.deformationScale(property).map { String($0) } ?? "" }
    private func apply() { store.setPartDeformationScale(part.id, property: property, value: draft) }
}
