import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// String drafts never retain a hidden last-valid value while displaying invalid input.
enum ComponentMeshSmoothingInput {
    static func value(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite, (0...180).contains(value) else { return nil }
        return value
    }
}

/// Full current state remains readable independently of the compact native menu label.
enum ComponentMeshFieldPresentation {
    static func title<Value>(_ value: ComponentMeshSelectionValue<Value>, render: (Value) -> String) -> String {
        switch value {
        case .uniform(let value): render(value)
        case .mixed: "Multiple values"
        case .unsupported: "Unsupported source value"
        }
    }
    static func combineAccessibilityLabel(count: Int) -> String {
        "Change combine mode for \(count) selected components"
    }
    static func combineAccessibilityValue(_ value: ComponentMeshSelectionValue<ComponentCombineMode>, count: Int)
        -> String
    {
        title(value, render: { $0.rawValue }) + "; \(count) selected components"
    }
}

/// Multi-row field authoring preserves the existing singleton inspector controls.
struct ComponentMeshSelectionControls: View {
    let store: EditorStore
    var body: some View {
        if let snapshot = store.snapshot, snapshot.selectedComponentIDs.count > 1 {
            let presentation = ComponentMeshSelectionPresentation(snapshot: snapshot)
            if presentation.isAvailable {
                ComponentMeshSelectionEditor(
                    store: store, presentation: presentation,
                    target: ComponentMeshSelectionTarget(snapshot: snapshot)
                )
                .id([
                    snapshot.documentIdentity.uuidString, String(snapshot.documentRevision),
                    String(snapshot.selectionRevision), String(snapshot.constraintRevision),
                ])
            }
        }
    }
}

private struct ComponentMeshSelectionEditor: View {
    let store: EditorStore
    let presentation: ComponentMeshSelectionPresentation
    let target: ComponentMeshSelectionTarget
    @State private var degrees = ""

    private var cutoffTitle: String {
        ComponentMeshFieldPresentation.title(presentation.smoothCutoffDegrees, render: { String($0) + "°" })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected component mesh settings").font(.headline).accessibilityAddTraits(.isHeader)
            Text(
                "Each explicit change applies to all \(target.count) selected components. Other settings stay as stored."
            )
            .font(.caption).foregroundStyle(.secondary)
            Text(
                "Combine mode: "
                    + ComponentMeshFieldPresentation.title(presentation.combineMode, render: { $0.rawValue })
            )
            .font(.caption).fixedSize(horizontal: false, vertical: true)
            Menu {
                ForEach(ComponentCombineMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue, action: store.componentMeshAction(.combineMode(mode), target: target))
                }
            } label: {
                Text("Change Combine Mode…")
            }
            .accessibilityLabel(ComponentMeshFieldPresentation.combineAccessibilityLabel(count: target.count))
            .accessibilityValue(
                ComponentMeshFieldPresentation.combineAccessibilityValue(presentation.combineMode, count: target.count)
            )
            .accessibilityIdentifier("multi-component-combine-mode")
            .help(
                "Normal unions, Inversion subtracts, and Uncombined retains separate geometry. Component order matters."
            )
            if presentation.showsSmoothing {
                Text("Normal smoothing: \(cutoffTitle)").font(.caption)
                TextField("Cutoff (°)", text: $degrees)
                    .accessibilityLabel("Selected components smoothing cutoff in degrees")
                    .accessibilityIdentifier("multi-component-smoothing-cutoff")
                    .focusedValue(\.editorTextEditing, true)
                    .onSubmit { store.componentMeshSmoothingAction(degrees, target: target)() }
                if !degrees.isEmpty && ComponentMeshSmoothingInput.value(degrees) == nil {
                    Text("Enter a finite cutoff from 0 to 180 degrees.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Reset Draft") { reset() }
                    Spacer()
                    Button("Apply Cutoff", action: store.componentMeshSmoothingAction(degrees, target: target))
                        .disabled(ComponentMeshSmoothingInput.value(degrees) == nil)
                        .accessibilityLabel("Apply smoothing cutoff to \(target.count) selected components")
                }
                Button("Set Sharp (0°)", action: store.componentMeshAction(.smoothCutoffDegrees(0), target: target))
                    .accessibilityLabel("Set zero smoothing cutoff on \(target.count) selected components")
                Text(
                    "Zero keeps sharp edges. An explicit cutoff replaces unsupported values. Each change is one Undo step."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .help("Selected components only; groups are not expanded. Cutoff affects normals, not authored node positions.")
        .disabled(!store.canEditComponentMeshSettings(target))
        .onAppear { reset() }
    }
    private func reset() {
        if case .uniform(let value) = presentation.smoothCutoffDegrees { degrees = String(value) } else { degrees = "" }
    }
}
