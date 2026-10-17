import Dust3DDocument
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
                        title(property),
                        isOn: Binding(
                            get: { value },
                            set: {
                                store.setComponentStitchingClosure(component.id, property: property, value: $0)
                            })
                    )
                    .accessibilityIdentifier("component-stitching-\(property.rawValue)")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(property)).font(.callout)
                        Picker(
                            title(property),
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
                        .accessibilityLabel(Text(title(property)))
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

    private func title(_ property: ComponentStitchingClosureProperty) -> String {
        switch property {
        case .front: return "Front closed"
        case .back: return "Back closed"
        case .side: return "Side closed"
        }
    }
}

private struct StitchingNumberControl: View {
    let title: String
    let identifier: String
    let identity: String
    let source: String?
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
                Text("Unsupported source value. Enter a replacement.").font(.caption).foregroundStyle(.primary)
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
