import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct ComponentStitchingControls: View {
    let store: EditorStore
    let component: DocumentComponent

    private var identity: String { (store.snapshot?.documentIdentity.uuidString ?? "") + component.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stitching").font(.headline)
            ForEach(ComponentStitchingClosureProperty.allCases, id: \.self) { property in
                if let value = component.stitching.closureValue(property) {
                    Toggle(
                        stitchingClosureTitle(property),
                        isOn: Binding(
                            get: { value },
                            set: {
                                store.setComponentStitchingClosure(component.id, property: property, value: $0)
                            })
                    )
                    .accessibilityIdentifier("component-stitching-\(property.rawValue)")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stitchingClosureTitle(property)).font(.callout)
                        Picker(
                            stitchingClosureTitle(property),
                            selection: Binding<Bool?>(
                                get: { nil },
                                set: {
                                    if let value = $0 {
                                        store.setComponentStitchingClosure(
                                            component.id, property: property, value: value)
                                    }
                                })
                        ) {
                            Text("Unsupported source value").tag(nil as Bool?).disabled(true)
                            Text("On").tag(Optional(true))
                            Text("Off").tag(Optional(false))
                        }
                        .labelsHidden().pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(Text(stitchingClosureTitle(property)))
                        .accessibilityIdentifier("component-stitching-\(property.rawValue)")
                    }
                }
            }
            StitchingNumberControl(
                title: "Target segments", identifier: "component-target-segments", identity: identity,
                source: component.stitching.targetSegments.map { String($0) }
            ) {
                store.setComponentTargetSegments(component.id, segments: $0)
            }
            ForEach(ComponentStitchingScalarProperty.allCases, id: \.self) { property in
                StitchingNumberControl(
                    title: property == .depthRatio ? "Loop cap depth" : "Loop cap sharpness",
                    identifier: "component-\(property.rawValue)", identity: identity,
                    source: component.stitching.scalarValue(property).map { String($0) }
                ) {
                    store.setComponentStitchingScalar(component.id, property: property, value: $0)
                }
            }
            Text(
                "Target segments: 0–100 (0 = automatic). Loop cap depth: 0–2; sharpness: 0–1. Each choice or Apply is one undo step."
            )
            .font(.caption).foregroundStyle(.primary)
            Text(
                "Line closures join spline ends and end profiles. Loop caps use Back closed and depend on profile orientation. These settings apply to stitching children in this group."
            )
            .font(.caption).foregroundStyle(.primary)
        }
    }

}

struct ComponentStitchingBatchControls: View {
    let store: EditorStore
    let target: ComponentStitchingBatchTarget
    let identity: String

    var body: some View {
        DisclosureGroup("Selected Group Stitching") {
            if target.supportsLine { closure(.front) }
            closure(.back)
            if target.supportsLine {
                closure(.side)
                number(
                    "Target segments (0–100; 0 = automatic)", identifier: "batch-stitching-segments",
                    value: target.targetSegments
                ) { store.setBatchStitchingSegments($0, target: target) }
            }
            if target.supportsLoop {
                number(
                    "Loop cap depth (0–2)", identifier: "batch-stitching-depth", value: target.scalar(.depthRatio)
                ) { store.setBatchStitchingScalar(.depthRatio, draft: $0, target: target) }
                number(
                    "Loop cap sharpness (0–1)", identifier: "batch-stitching-sharpness",
                    value: target.scalar(.sharpness)
                ) { store.setBatchStitchingScalar(.sharpness, draft: $0, target: target) }
            }
            Text("Each edit applies to all selected groups and can be undone in one step.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!store.canEditComponentStitchingBatch(target))
    }

    @ViewBuilder private func closure(_ property: ComponentStitchingClosureProperty) -> some View {
        let title = stitchingClosureTitle(property)
        let value = target.closure(property)
        if case .uniform(let current) = value {
            Toggle(title, isOn: Binding(get: { current }, set: { apply(property, $0) }))
        } else {
            let status = value == .mixed ? "Mixed values" : "Unsupported source value"
            Menu("\(title): \(status)") {
                Button("On") { apply(property, true) }
                Button("Off") { apply(property, false) }
            }
            .accessibilityLabel(title)
            .accessibilityValue(status)
        }
    }

    private func apply(_ property: ComponentStitchingClosureProperty, _ value: Bool) {
        store.editComponentStitchingBatch(.closure(property, value), target: target)
    }

    private func number<Value: Equatable & Sendable>(
        _ title: String, identifier: String, value: ComponentMeshSelectionValue<Value>,
        apply: @escaping (String) -> Void
    ) -> some View {
        let source: String?
        if case .uniform(let current) = value {
            source = String(describing: current)
        } else {
            source = nil
        }
        return StitchingNumberControl(
            title: title, identifier: identifier, identity: identity, source: source,
            nilNotice: value == .mixed
                ? "Mixed values. Enter a replacement." : "Unsupported source value. Enter a replacement.",
            apply: apply)
    }
}

private func stitchingClosureTitle(_ property: ComponentStitchingClosureProperty) -> String {
    switch property {
    case .front: "Front closed"
    case .back: "Back closed"
    case .side: "Side closed"
    }
}

private struct StitchingNumberControl: View {
    let title: String
    let identifier: String
    let identity: String
    let source: String?
    var nilNotice = "Unsupported source value. Enter a replacement."
    let apply: (String) -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextField(title, text: $draft)
                .accessibilityIdentifier(identifier)
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { apply(draft) }
            if source == nil {
                Text(nilNotice).font(.caption).foregroundStyle(.primary)
            }
            HStack {
                Button("Reset Draft") { reset() }.accessibilityLabel("Reset \(title.lowercased()) draft")
                Spacer()
                Button("Apply") { apply(draft) }.accessibilityLabel("Apply \(title.lowercased())")
            }
        }
        .onChange(of: identity, initial: true) { _, _ in reset() }
        .onChange(of: source) { _, _ in reset() }
    }

    private func reset() { draft = source ?? "" }
}
