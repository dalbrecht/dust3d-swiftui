import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// Finish controls are tied to the rendered document/selection epoch, including local native picker sessions.
struct ComponentSurfaceControls: View {
    let store: EditorStore
    let component: DocumentComponent
    var body: some View {
        if let snapshot = store.snapshot, snapshot.selectedComponent == component,
            component.wrapping.mode == .skin || component.wrapping.mode == .cloth
        {
            let target = ComponentSurfaceTarget(snapshot: snapshot)
            SurfaceDetailEditor(store: store, component: component, target: target)
                .id([
                    snapshot.documentIdentity.uuidString, String(snapshot.documentRevision),
                    String(snapshot.selectionRevision), String(snapshot.constraintRevision), component.id,
                ])
        }
    }
}

private struct SurfaceDetailEditor: View {
    let store: EditorStore
    let component: DocumentComponent
    let target: ComponentSurfaceTarget
    private var details: ComponentSurfaceDetails { component.wrapping.surfaceDetails }
    private var patternTitle: String {
        details.pattern.map { $0 == .none ? "None" : $0.rawValue } ?? "Unsupported source"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Surface finish").font(.headline).accessibilityAddTraits(.isHeader)
            Menu {
                ForEach(ComponentSurfacePattern.allCases, id: \.self) { pattern in
                    Button(
                        pattern == .none ? "None" : pattern.rawValue,
                        action: store.componentSurfaceAction(.pattern(pattern), target: target))
                }
            } label: {
                Text("Pattern: " + patternTitle)
            }
            .accessibilityLabel("Wrapping surface pattern")
            .accessibilityValue(Text(patternTitle))
            .accessibilityIdentifier("component-surface-pattern")
            if details.pattern == nil {
                Text("Unsupported source pattern is retained. Choose a replacement.").font(.caption)
            }
            if details.pattern != ComponentSurfacePattern.none {
                SurfaceInkControls(
                    source: details.ink, canEdit: { store.canEditComponentSurface(target) },
                    apply: store.componentSurfaceInkAction(target: target),
                    automatic: store.componentSurfaceAction(.ink(nil), target: target))
                number(.patternScale, title: "Pattern size")
            }
            number(.belly, title: "Lighter belly")
            Text("Lighter belly applies when a pattern is selected.").font(.caption)
            number(.wrinkles, title: "Wrinkles")
            number(.wrinkleSize, title: "Wrinkle size")
            Text(
                "Patterns change baked color; wrinkles change the baked normal map. Apply is one undo step. Preview preparation runs in the background."
            )
            .font(.caption)
        }
        .disabled(!store.canEditComponentSurface(target))
    }
    private func number(_ property: ComponentSurfaceScalar, title: String) -> some View {
        SurfaceNumberControl(
            title: title, property: property, source: details.scalarValue(property),
            apply: store.componentSurfaceScalarAction(property, target: target))
    }
}

struct SurfaceInkControls: View {
    let source: ComponentColorValue
    let canEdit: @MainActor () -> Bool
    let apply: @MainActor (DocumentColor) -> Void
    let automatic: @MainActor () -> Void
    @State private var draft: SurfaceInkDraft

    init(
        source: ComponentColorValue, draft: SurfaceInkDraft? = nil, canEdit: @escaping @MainActor () -> Bool,
        apply: @escaping @MainActor (DocumentColor) -> Void, automatic: @escaping @MainActor () -> Void
    ) {
        self.source = source
        self.canEdit = canEdit
        self.apply = apply
        self.automatic = automatic
        _draft = State(initialValue: draft ?? SurfaceInkDraft(source: source))
    }
    var body: some View {
        let choose = draft.choosingAction(canEdit: canEdit)
        let edit = draft.editingAction(canEdit: canEdit)
        VStack(alignment: .leading, spacing: 6) {
            Text("Pattern ink").font(.callout)
            if case .unsupported(let text) = source {
                Text("Unsupported source ink: " + ComponentColorDraft.sourceSummary(text)).font(.caption)
            } else if source == .unset {
                Text("Automatic: a dark tone of the base color.").font(.caption)
            }
            ColorPicker(
                "Ink color draft",
                selection: Binding(
                    get: {
                        DocumentColorPresentation.color(draft.color.parsedColor ?? .init(red: 40, green: 30, blue: 20))
                    },
                    set: { choose(DocumentColorPresentation.value(from: $0)) }), supportsOpacity: false
            )
            .id(draft.generation)
            .accessibilityIdentifier("component-surface-ink-picker")
            TextField("Ink hex RGB", text: Binding(get: { draft.color.text }, set: { value in edit(value) }))
                .accessibilityIdentifier("component-surface-ink-hex")
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
            if let issue = draft.color.conversionIssue {
                Text(issue.message).font(.caption)
            } else if !draft.color.text.isEmpty && !draft.canApply {
                Text("Enter an opaque #RRGGBB color.").font(.caption)
            }
            HStack {
                Button("Cancel Draft", action: cancel).accessibilityLabel("Cancel pattern ink draft")
                Spacer()
                Button("Apply Ink", action: commit).disabled(!draft.canApply)
            }
            Button("Automatic Ink", action: automatic).disabled(source == .unset)
        }
        .onChange(of: source) { _, value in draft.cancel(source: value) }
    }
    private func cancel() { draft.cancel(source: source) }
    private func commit() {
        guard canEdit(), draft.canApply, let color = draft.color.parsedColor else { return }
        apply(color)
    }
}

private struct SurfaceNumberControl: View {
    let title: String
    let property: ComponentSurfaceScalar
    let source: Double?
    let apply: @MainActor (String) -> Void
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextField(title, text: $draft)
                .accessibilityIdentifier("component-surface-" + property.rawValue)
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { apply(draft) }
                .onExitCommand { reset() }
            Text(String(property.bounds.lowerBound) + "–" + String(property.bounds.upperBound)).font(.caption)
            if source == nil { Text("Unsupported source value. Apply a replacement.").font(.caption) }
            HStack {
                Button("Reset Draft", action: reset).accessibilityLabel("Reset \(title.lowercased()) draft")
                Spacer()
                Button("Apply") { apply(draft) }.accessibilityLabel("Apply \(title.lowercased())")
            }
        }
        .onChange(of: source, initial: true) { _, _ in reset() }
    }
    private func reset() { draft = source.map { String($0) } ?? "" }
}
