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
            ComponentColorDraftPreviewControls(
                store: store, target: store.componentColorDraftPreviewTarget(componentID: component.id), draft: draft)
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

struct ComponentBatchColorControls: View {
    let store: EditorStore
    let target: ComponentMeshSelectionTarget
    @State private var draft = ComponentColorDraft(source: .unset)

    private var scope: String { target.isGraphSelection ? "owning components" : "selected components" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(target.isGraphSelection ? "Component color draft" : "Selected Component Colors").font(.headline)
            ColorPicker(
                "Color draft",
                selection: Binding(
                    get: { DocumentColorPresentation.color(draft.pickerColor) },
                    set: { draft = draft.choosing(DocumentColorPresentation.value(from: $0)) }
                ), supportsOpacity: true)
            TextField(
                "Hex color",
                text: Binding(
                    get: { draft.text },
                    set: { draft = draft.editing($0) }
                ), prompt: Text("#RRGGBB or #AARRGGBB")
            )
            .accessibilityLabel(
                target.isGraphSelection
                    ? "Owning components’ hex color, alpha first"
                    : "Selected components’ hex color, alpha first"
            )
            .focusedValue(\.editorTextEditing, true)
            .onSubmit { apply() }
            .onExitCommand { draft = ComponentColorDraft(source: .unset) }
            if let conversionIssue = draft.conversionIssue {
                Text(conversionIssue.message).font(.caption)
            }
            HStack {
                Button("Apply Color", action: apply)
                    .disabled(!draft.canApply)
                    .accessibilityLabel("Apply color to \(scope)")
                Button("Clear Colors") { store.setSelectedComponentColors(target, value: nil) }
                    .accessibilityLabel("Clear colors from \(scope)")
            }
            ComponentColorDraftPreviewControls(
                store: store, target: store.componentColorDraftPreviewTarget(selection: target), draft: draft)
            Text(
                target.isGraphSelection
                    ? "Changes apply to the components that own the graph picks."
                    : "Changes apply to selected component rows."
            )
            .font(.caption)
        }
        .disabled(!store.canEditSelectedComponentColors(target))
        .accessibilityElement(children: .contain)
    }
    private func apply() {
        guard draft.canApply else { return }
        store.setSelectedComponentColors(target, value: draft.text)
    }

}

private struct ComponentColorDraftPreviewControls: View {
    let store: EditorStore
    let target: ComponentColorDraftPreviewTarget?
    let draft: ComponentColorDraft

    private var color: DocumentColor? { draft.conversionIssue == nil ? draft.parsedColor : nil }

    var body: some View {
        if let target {
            let active = store.isComponentColorDraftPreviewActive(target: target)
            if active {
                Button("Stop Color Draft Preview") { store.stopComponentColorDraftPreview(target: target) }
                    .onChange(of: color) { _, color in
                        store.updateComponentColorDraftPreview(color, target: target)
                    }
                    .onDisappear { store.stopComponentColorDraftPreview(target: target) }
            } else {
                Button("Preview Color Draft") {
                    if let color { store.startComponentColorDraftPreview(color, target: target) }
                }
                .disabled(color == nil)
                .help("Preview the solid colors on the model before applying them to the document.")
            }
        }
    }
}
