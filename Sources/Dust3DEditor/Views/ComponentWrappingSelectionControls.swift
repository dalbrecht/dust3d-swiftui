import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// Explicit field replacements for directly selected groups; mixed values never become implicit edits.
struct ComponentWrappingSelectionControls: View {
    let store: EditorStore
    var body: some View {
        if let snapshot = store.snapshot, snapshot.selectedComponentIDs.count > 1 {
            let presentation = ComponentWrappingSelectionPresentation(snapshot: snapshot)
            if presentation.isAvailable {
                let target = ComponentWrappingSelectionTarget(snapshot: snapshot)
                MultiWrappingEditor(store: store, presentation: presentation, target: target)
                    .id([
                        snapshot.documentIdentity.uuidString, String(snapshot.documentRevision),
                        String(snapshot.selectionRevision), String(snapshot.constraintRevision),
                    ])
            }
        }
    }
}

private struct MultiWrappingEditor: View {
    let store: EditorStore
    let presentation: ComponentWrappingSelectionPresentation
    let target: ComponentWrappingSelectionTarget
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected group wrapping").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Each explicit change applies to every selected group. Other settings and modes stay as stored.").font(
                .caption)
            Menu {
                ForEach(ComponentWrapMode.allCases, id: \.self) { mode in
                    Button(ComponentWrappingPresentation.modeTitle(mode), action: action(.mode(mode)))
                }
            } label: {
                Text("Mode: " + title(presentation.mode) { ComponentWrappingPresentation.modeTitle($0) })
            }
            .accessibilityLabel("Selected groups wrapping mode")
            .accessibilityValue(title(presentation.mode) { ComponentWrappingPresentation.modeTitle($0) })
            .accessibilityIdentifier("multi-wrap-mode")
            Menu {
                Button("On", action: action(.keepChildren(true)))
                Button("Off", action: action(.keepChildren(false)))
            } label: {
                Text("Keep children: " + title(presentation.keepChildren) { $0 ? "On" : "Off" })
            }
            .accessibilityLabel("Selected groups keep children")
            .accessibilityValue(title(presentation.keepChildren) { $0 ? "On" : "Off" })
            .accessibilityIdentifier("multi-wrap-keep")
            number(
                "Target Faces", source: title(presentation.faces, render: String.init), identifier: "faces",
                help: "64–20000, whole numbers. Generated face count can differ."
            ) { Int($0).map(ComponentWrappingEdit.targetFaces) }
            ForEach(ComponentWrappingScalarProperty.allCases, id: \.self) { property in
                if property == .offset || property == .smoothness || presentation.showsClothFields {
                    let field = fieldTitle(property)
                    number(
                        field, source: title(presentation.scalar(property), render: { String($0) }),
                        identifier: property.rawValue, help: "0–\(property.bounds.upperBound)"
                    ) { text in
                        EngineScalar.parse(text, in: property.bounds).map { .scalar(property, $0) }
                    }
                }
            }
            if presentation.showsClothFields {
                Text("Drape, openings and thickness affect Cloth. Edits are also stored on every other selected group.")
                    .font(.caption)
            }
            Text("Surface finish").font(.headline)
            Menu {
                ForEach(ComponentSurfacePattern.allCases, id: \.self) { pattern in
                    Button(pattern == .none ? "None" : pattern.rawValue, action: action(.surfacePattern(pattern)))
                }
            } label: {
                Text("Pattern: " + title(presentation.pattern) { $0 == .none ? "None" : $0.rawValue })
            }
            .accessibilityLabel("Selected groups wrapping surface pattern")
            .accessibilityValue(title(presentation.pattern) { $0 == .none ? "None" : $0.rawValue })
            .accessibilityIdentifier("multi-wrap-pattern")
            number(
                "Pattern ink #RRGGBB",
                source: title(presentation.ink) { value in
                    switch value {
                    case .unset: return "Automatic"
                    case .value(let color): return color.archiveValue
                    case .unsupported: return "Unsupported source"
                    }
                }, identifier: "ink", help: "Opaque RGB. Cancel Draft leaves every source ink unchanged."
            ) { text in
                guard let color = DocumentColor(archiveValue: text), color.alpha == 255 else { return nil }
                return .surfaceInk(color)
            }
            Button("Automatic Ink", action: action(.surfaceInk(nil)))
            ForEach(ComponentSurfaceScalar.allCases, id: \.self) { property in
                number(
                    surfaceTitle(property), source: title(presentation.surfaceScalar(property), render: { String($0) }),
                    identifier: property.rawValue, help: "\(property.bounds.lowerBound)–\(property.bounds.upperBound)"
                ) { text in
                    EngineScalar.parse(text, in: property.bounds).map { .surfaceScalar(property, $0) }
                }
            }
            Text("Lighter belly applies when a pattern is selected. Surface finish is visible on active Skin or Cloth.")
                .font(.caption)
        }
        .disabled(!store.canEditComponentWrappingSelection(target))
    }
    private func action(_ edit: ComponentWrappingEdit) -> @MainActor () -> Void {
        store.componentWrappingSelectionAction(edit, target: target)
    }
    private func number(
        _ label: String, source: String, identifier: String, help: String,
        edit: @escaping @MainActor (String) -> ComponentWrappingEdit?
    ) -> some View {
        MultiWrappingNumber(
            label: label, source: source, identifier: identifier, help: help,
            apply: store.componentWrappingSelectionNumberAction(target: target, edit: edit))
    }
    private func title<T>(_ value: ComponentWrappingSelectionValue<T>, render: (T) -> String) -> String {
        switch value {
        case .uniform(let value): return render(value)
        case .mixed: return "Multiple values"
        case .unsupported: return "Unsupported source"
        }
    }
    private func fieldTitle(_ property: ComponentWrappingScalarProperty) -> String {
        switch property {
        case .offset: return "Offset"
        case .smoothness: return "Smoothness"
        case .drape: return "Drape"
        case .drapeLength: return "Drape length"
        case .openTop: return "Open top"
        case .openBottom: return "Open bottom"
        case .thickness: return "Thickness"
        }
    }
    private func surfaceTitle(_ property: ComponentSurfaceScalar) -> String {
        switch property {
        case .patternScale: return "Pattern size"
        case .belly: return "Lighter belly"
        case .wrinkles: return "Wrinkles"
        case .wrinkleSize: return "Wrinkle size"
        }
    }
}

private struct MultiWrappingNumber: View {
    let label: String
    let source: String
    let identifier: String
    let help: String
    let apply: @MainActor (String) -> Void
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout)
            Text("Current: " + source).font(.caption)
            TextField("Replacement " + label, text: $draft)
                .accessibilityIdentifier("multi-wrap-" + identifier)
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { if !draft.isEmpty { apply(draft) } }
                .onExitCommand { draft = "" }
            Text(help).font(.caption)
            HStack {
                Button("Cancel Draft") { draft = "" }.accessibilityLabel("Cancel selected groups " + label + " draft")
                Spacer()
                Button("Apply") { apply(draft) }.disabled(draft.isEmpty)
                    .accessibilityLabel("Apply selected groups " + label)
            }
        }
    }
}
