import SwiftUI

/// Explicit commands remain accessible outside native canvas keyboard focus.
struct CanvasPrecisionControls: View {
    let store: EditorStore
    var body: some View {
        DisclosureGroup("Nudge and Spacing") { CanvasPrecisionPanel(store: store) }
            .accessibilityLabel("Precision canvas controls")
    }
}

struct CanvasPrecisionPanel: View {
    let store: EditorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.isMovingOrigin ? "Nudge Document Origin" : "Nudge Graph Selection").font(.headline)
            Text(store.plane.rawValue).font(.caption).foregroundStyle(.secondary)
            HStack {
                precisionButton(.left)
                precisionButton(.right)
            }
            HStack {
                precisionButton(.up)
                precisionButton(.down)
            }
            Text("Selected Node Spacing").font(.headline)
            precisionButton(.decreaseSpacing)
            precisionButton(.increaseSpacing)
            Text(
                "Spacing changes all position axes around the selection center. Radii stay unchanged. Arrow and bracket keys work only with canvas focus."
            )
            .font(.caption).foregroundStyle(.secondary)
            if store.canvasHeight > 0 {
                Text(
                    "Nudge step: \( (1 / store.canvasHeight).formatted(.number.precision(.fractionLength(0...6))) ) document units"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func precisionButton(_ action: CanvasPrecisionAction) -> some View {
        Button(action.label, action: store.canvasPrecisionAction(action)).disabled(
            !store.canPerformCanvasPrecision(action))
    }
}

@MainActor struct CanvasPrecisionActions {
    struct Entry {
        let action: CanvasPrecisionAction
        let enabled: Bool
        let invoke: @MainActor () -> Void
    }
    let entries: [Entry]
    init(store: EditorStore?, isInScope: @escaping @MainActor () -> Bool = { true }) {
        entries = CanvasPrecisionAction.allCases.map { action in
            guard isInScope(), let store, store.canPerformCanvasPrecision(action) else {
                return Entry(action: action, enabled: false, invoke: {})
            }
            let invoke = store.canvasPrecisionAction(action)
            return Entry(action: action, enabled: true) {
                if isInScope() { invoke() }
            }
        }
    }
}

struct CanvasPrecisionMenu: View {
    let actions: CanvasPrecisionActions
    let contextual: Bool
    init(actions: CanvasPrecisionActions, contextual: Bool = false) {
        self.actions = actions
        self.contextual = contextual
    }
    var body: some View {
        let entries = contextual ? actions.entries.filter(\.enabled) : actions.entries
        if !contextual || !entries.isEmpty {
            Menu("Nudge and Spacing") {
                ForEach(entries, id: \.action) { entry in
                    Button(entry.action.label, action: entry.invoke).disabled(!entry.enabled)
                }
            }
            .disabled(entries.allSatisfy { !$0.enabled })
            .help(
                "Arrow and bracket keys apply only while a canvas input view has focus. These menu commands can also be chosen directly."
            )
        }
    }
}
