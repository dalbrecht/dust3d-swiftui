import SwiftUI

/// Qt's Colorize actions target explicit node-owned parts; Auto also samples explicit edge midpoints.
struct GraphColorizeControls: View {
    let store: EditorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Clear Part Colors", action: store.clearSelectionColorsAction())
                    .disabled(!store.canClearSelectionColors)
                Button("Auto Color", action: store.referenceColorAction())
                    .disabled(!store.canAutoColorSelection)
            }
            if store.isPreparingReferenceColors {
                ProgressView("Preparing reference colors…").controlSize(.small)
            }
            if let error = store.referenceColorError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption)
            }
            if let notice = store.referenceColorNotice { Text(notice).font(.caption) }
            Text(
                "Use the reference image to color selected parts. Selected edges also contribute. Clear removes part colors; reference and texture images remain."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colorize graph selection")
    }
}

struct GraphColorizeMenu: View {
    let actions: GraphColorizeActions
    let contextual: Bool
    init(store: EditorStore?, contextual: Bool = false) {
        actions = GraphColorizeActions(store: store)
        self.contextual = contextual
    }
    init(actions: GraphColorizeActions, contextual: Bool = false) {
        self.actions = actions
        self.contextual = contextual
    }
    var body: some View {
        if !contextual || actions.canClear || actions.canAutoColor {
            Menu("Colorize Selection") {
                if !contextual || actions.canClear {
                    Button("Clear Part Colors", action: actions.clear).disabled(!actions.canClear)
                }
                if !contextual || actions.canAutoColor {
                    Button("Auto Color", action: actions.autoColor).disabled(!actions.canAutoColor)
                }
            }
            .disabled(!actions.canClear && !actions.canAutoColor)
            .help(
                "Select at least one node. Auto Color also samples selected edge midpoints. Repeated source colors count once; locked parts and positions outside the reference are skipped."
            )
        }
    }
}
