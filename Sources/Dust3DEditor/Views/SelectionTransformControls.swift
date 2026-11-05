import SwiftUI

/// Numeric transforms use the editable union of selected nodes and edge endpoints.
struct SelectionTransformControls: View {
    let store: EditorStore
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var z = 0.0
    @State private var positionFactor = 1.0
    @State private var radiusFactor = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move by document units").font(.headline)
            Form {
                TextField("Δ X", value: $x, format: .number).disabled(store.locks.contains(.x))
                TextField("Δ Y", value: $y, format: .number).disabled(store.locks.contains(.y))
                TextField("Δ Z", value: $z, format: .number).disabled(store.locks.contains(.z))
            }
            .focusedValue(\.editorTextEditing, true)
            Button("Move Selection") { store.moveSelection(by: .init(x: x, y: y, z: z)) }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Move Selection")
            Divider()
            Text("Scale around selection center").font(.headline)
            Form {
                TextField("Positions ×", value: $positionFactor, format: .number)
                    .disabled(store.locks.isSuperset(of: [.x, .y, .z]))
                TextField("Radii ×", value: $radiusFactor, format: .number)
                    .disabled(store.locks.contains(.radius))
            }
            .focusedValue(\.editorTextEditing, true)
            Button("Scale Selection") {
                store.scaleSelection(positionFactor: positionFactor, radiusFactor: radiusFactor)
            }
            .accessibilityLabel("Scale Selection")
            Text("Positive factors. 1 keeps the current size. The center uses editable nodes only.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!store.canTransform)
    }
}
