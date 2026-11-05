import SwiftUI

struct NodeRadiusAdjustmentControls: View {
    let store: EditorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Decrease Radius") { store.adjustSelectionRadius(direction: -1) }
                Button("Increase Radius") { store.adjustSelectionRadius(direction: 1) }
            }
            .disabled(!store.canAdjustSelectionRadius)
            Text("Adjusts selected nodes and selected edge endpoints by the same amount.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Adjust node radii")
    }
}
