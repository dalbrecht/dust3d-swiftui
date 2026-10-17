import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct ComponentWrappingControls: View {
    let store: EditorStore
    let component: DocumentComponent
    private var presentation: ComponentWrappingPresentation { .init(component: component) }
    private var identity: [String] {
        [
            store.snapshot?.documentIdentity.uuidString ?? "", component.id,
            component.wrapping.mode?.rawValue ?? "unsupported",
        ]
    }

    var body: some View {
        if presentation.isAvailable {
            VStack(alignment: .leading, spacing: 8) {
                Text("Wrapping").font(.headline).accessibilityAddTraits(.isHeader)
                modePicker
                if component.wrapping.mode == nil {
                    Text("Unsupported source mode. Choose a replacement.").font(.caption).foregroundStyle(.primary)
                }
                if presentation.showsSettings {
                    keepChildren
                    WrappingNumberControl(
                        title: "Faces", identifier: "component-wrap-faces", identity: identity,
                        source: component.wrapping.targetFaces.map { String($0) }, range: "64–20000, whole numbers"
                    ) { store.setComponentWrapFaces(component.id, faces: $0) }
                    ForEach(presentation.fields) { field in
                        WrappingNumberControl(
                            title: field.title, identifier: "component-\(field.property.rawValue)", identity: identity,
                            source: component.wrapping.scalarValue(field.property).map { String($0) },
                            range: field.rangeDescription
                        ) { store.setComponentWrapScalar(component.id, property: field.property, value: $0) }
                    }
                    Text(
                        "Apply or Return saves a number. Reset Draft discards typed changes. Changes use one undo step."
                    )
                    .font(.caption).foregroundStyle(.primary)
                } else if component.wrapping.mode != nil {
                    Text("Choose Skin or Cloth to wrap this group.").font(.caption).foregroundStyle(.primary)
                }
            }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Wrapping mode").font(.callout)
            Picker(
                "Wrapping mode",
                selection: Binding<ComponentWrapMode?>(
                    get: { component.wrapping.mode },
                    set: { if let mode = $0 { store.setComponentWrapMode(component.id, mode: mode) } })
            ) {
                if component.wrapping.mode == nil {
                    Text("Unsupported source mode").tag(nil as ComponentWrapMode?).disabled(true)
                }
                ForEach(ComponentWrapMode.allCases, id: \.self) { mode in
                    Text(ComponentWrappingPresentation.modeTitle(mode)).tag(Optional(mode))
                }
            }
            .accessibilityIdentifier("component-wrap-mode")
            .help("Skin creates a close-fitting surface. Cloth adds drape and openings.")
            .labelsHidden().pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text("Wrapping mode"))
        }
    }

    @ViewBuilder private var keepChildren: some View {
        if let value = component.wrapping.keepsChildren {
            Toggle(
                "Keep children",
                isOn: Binding(get: { value }, set: { store.setComponentWrapKeepChildren(component.id, value: $0) })
            )
            .accessibilityIdentifier("component-wrap-keep")
            .help("Include the original parts beneath the wrapping surface.")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep children").font(.callout)
                Picker(
                    "Keep children",
                    selection: Binding<Bool?>(
                        get: { nil },
                        set: { if let value = $0 { store.setComponentWrapKeepChildren(component.id, value: value) } })
                ) {
                    Text("Unsupported source value").tag(nil as Bool?).disabled(true)
                    Text("On").tag(Optional(true))
                    Text("Off").tag(Optional(false))
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text("Keep children"))
                .accessibilityIdentifier("component-wrap-keep")
            }
        }
    }
}

private struct WrappingNumberControl: View {
    let title: String
    let identifier: String
    let identity: [String]
    let source: String?
    let range: String
    let apply: (String) -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextField(title, text: $draft)
                .accessibilityIdentifier(identifier)
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { apply(draft) }
            Text(range).font(.caption).foregroundStyle(.primary)
            if source == nil {
                Text("Unsupported source value. Enter a replacement.").font(.caption).foregroundStyle(.primary)
            }
            HStack {
                Button("Reset Draft") { reset() }
                    .accessibilityLabel("Reset wrapping \(title.lowercased()) draft")
                    .accessibilityIdentifier(identifier + "-reset")
                Spacer()
                Button("Apply") { apply(draft) }
                    .accessibilityLabel("Apply wrapping \(title.lowercased())")
                    .accessibilityIdentifier(identifier + "-apply")
            }
        }
        .onChange(of: identity, initial: true) { _, _ in reset() }
        .onChange(of: source) { _, _ in reset() }
    }

    private func reset() { draft = source ?? "" }
}
