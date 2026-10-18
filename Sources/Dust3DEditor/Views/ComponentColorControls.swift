import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct ComponentColorControls: View {
    let store: EditorStore
    let component: DocumentComponent
    @State private var draft = ComponentColorDraft(source: .unset)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Component color").font(.headline)
            sourceDescription
            ColorPicker("Color draft", selection: pickerColor, supportsOpacity: true)
                .accessibilityIdentifier("component-color-picker")
            Text("Hex color · #RRGGBB or #AARRGGBB").font(.caption)
            TextField(
                "Hex color",
                text: Binding(
                    get: { draft.text },
                    set: { draft = draft.editing($0) })
            )
            .font(.system(.body, design: .monospaced))
            .accessibilityLabel("Component hex color, alpha first")
            .accessibilityIdentifier("component-color-hex")
            .focusedValue(\.editorTextEditing, true)
            .onSubmit { apply() }
            .onExitCommand { reset() }
            if let conversionIssue = draft.conversionIssue {
                Text(conversionIssue.message).font(.caption).foregroundStyle(.primary)
            }
            HStack {
                Button(action: reset) { Text("Reset Draft").frame(minHeight: 32) }
                    .accessibilityLabel("Reset component color draft")
                Spacer()
                Button(action: apply) { Text("Apply").frame(minHeight: 32) }
                    .accessibilityLabel("Apply component color")
                    .disabled(!draft.canApply)
            }
            Button {
                store.removeComponentColor(component.id)
            } label: {
                Text("Use Default Color").frame(maxWidth: .infinity, minHeight: 32)
            }
            .accessibilityLabel("Remove explicit component color")
            .disabled(component.color == .unset)
            Text("Apply is one undo step. Color and opacity update the material preview in the background.")
                .font(.caption).foregroundStyle(.primary)
        }
        .onChange(of: component.id, initial: true) { _, _ in reset() }
        .onChange(of: component.color) { _, _ in reset() }
    }

    @ViewBuilder private var sourceDescription: some View {
        switch component.color {
        case .unset:
            Text("No explicit color. Choose a draft to add one.").font(.caption)
        case .value:
            EmptyView()
        case .unsupported(let raw):
            Text("Unsupported source color. Apply a replacement or use the default.").font(.caption)
            Text("Source: \(ComponentColorDraft.sourceSummary(raw))").font(.caption).textSelection(.enabled)
                .focusedValue(\.editorTextEditing, true)
        }
    }

    private var pickerColor: Binding<Color> {
        Binding(
            get: { DocumentColorPresentation.color(draft.pickerColor) },
            set: { draft = draft.choosing(DocumentColorPresentation.value(from: $0)) })
    }

    private func reset() { draft = ComponentColorDraft(source: component.color) }
    private func apply() {
        guard draft.canApply else { return }
        store.setComponentColor(component.id, value: draft.text)
    }
}
