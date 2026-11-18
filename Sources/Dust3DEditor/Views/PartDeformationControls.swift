import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct PartDeformationControls: View {
    let store: EditorStore
    let part: DocumentPart
    var graphTarget: GraphPartCrossSectionTarget? = nil
    var inspectorTarget: CanvasAdjustmentTarget? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cross-section deformation").font(.headline)
            ForEach(PartDeformationProperty.allCases, id: \.self) { property in
                PartDeformationScaleControl(
                    store: store, part: part, property: property, graphTarget: graphTarget,
                    inspectorTarget: inspectorTarget
                )
            }
            if !part.isImportedModel {
                if let value = part.isDeformationUnified {
                    Toggle(
                        "Unified deformation",
                        isOn: Binding(get: { value }, set: { setUnified($0) })
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
                                    if let value = $0 { setUnified(value) }
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
            }
            Text(
                "Scales range from 0 to 2; 1 preserves the original cross-section. Each applied change is one undo step."
            )
            .font(.caption).foregroundStyle(.primary)
        }
    }

    private func setUnified(_ value: Bool) {
        if let graphTarget {
            store.editGraphPartCrossSection(.deformationUnified(value), target: graphTarget)
        } else if let inspectorTarget {
            store.setPartDeformationUnified(part.id, value: value, target: inspectorTarget)
        }
    }
}

private struct PartDeformationScaleControl: View {
    let store: EditorStore
    let part: DocumentPart
    let property: PartDeformationProperty
    let graphTarget: GraphPartCrossSectionTarget?
    let inspectorTarget: CanvasAdjustmentTarget?
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
                if let resetScale = resetScaleAction {
                    Button("Reset to 1") { resetScale() }
                        .accessibilityLabel("Reset \(title.lowercased()) to 1")
                        .disabled(part.deformationScale(property) == 1)
                }
                Spacer()
                Button("Apply") { apply() }
                    .accessibilityLabel("Apply \(title.lowercased())")
            }
        }
        .onChange(of: part.id, initial: true) { _, _ in reset() }
        .onChange(of: part.deformationScale(property)) { _, _ in reset() }
    }

    private func reset() { draft = part.deformationScale(property).map { String($0) } ?? "" }
    private var resetScaleAction: (@MainActor () -> Void)? {
        if let graphTarget {
            return { store.editGraphPartCrossSection(.deformationScale(property, 1), target: graphTarget) }
        }
        return store.partDeformationResetAction(property, partID: part.id)
    }

    private func apply() {
        if let graphTarget {
            store.setGraphPartDeformationScale(property, value: draft, target: graphTarget)
        } else if let inspectorTarget {
            store.setPartDeformationScale(part.id, property: property, value: draft, target: inspectorTarget)
        }
    }
}
