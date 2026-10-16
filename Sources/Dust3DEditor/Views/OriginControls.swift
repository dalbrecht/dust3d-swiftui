import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct OriginControls: View {
    let store: EditorStore
    @State private var x = ""
    @State private var y = ""
    @State private var z = ""

    var body: some View {
        DisclosureGroup("Document Origin") {
            VStack(alignment: .leading, spacing: 12) {
                if store.snapshot?.origin == nil {
                    Text(
                        "Stored origin is missing or unsupported. Enter all three coordinates to set it explicitly; unlock position axes first."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("X").frame(width: 12)
                    TextField("Origin X", text: $x).accessibilityIdentifier("origin-x")
                        .disabled(store.locks.contains(.x))
                        .focusedValue(\.editorTextEditing, true)
                }
                HStack {
                    Text("Y").frame(width: 12)
                    TextField("Origin Y", text: $y).accessibilityIdentifier("origin-y")
                        .disabled(store.locks.contains(.y))
                        .focusedValue(\.editorTextEditing, true)
                }
                HStack {
                    Text("Z").frame(width: 12)
                    TextField("Origin Z", text: $z).accessibilityIdentifier("origin-z")
                        .disabled(store.locks.contains(.z))
                        .focusedValue(\.editorTextEditing, true)
                }
                HStack {
                    Button("Reset Draft") { reset() }
                    Spacer()
                    Button("Apply Origin") { store.setOrigin(x: x, y: y, z: z) }
                }
                Button("Center Origin on Model") { store.centerOriginOnModel() }
                    .help(
                        "Center all node radius bounds, including hidden or disabled parts. Axis locks apply. Empty models target zero."
                    )
                Text(
                    "Changes mesh placement without moving document nodes. Axis locks apply; each change is one undo step. Coordinates must be finite and within ±1,000,000. Zero is valid; no automatic settlement is performed."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 8)
        }
        .disabled(store.isWorking || store.snapshot == nil)
        .onChange(of: store.snapshot?.origin, initial: true) { _, _ in reset() }
        .onChange(of: store.locks) { previous, current in
            let origin = store.snapshot?.origin
            if current.contains(.x) && !previous.contains(.x) { x = origin.map { String($0.x) } ?? "" }
            if current.contains(.y) && !previous.contains(.y) { y = origin.map { String($0.y) } ?? "" }
            if current.contains(.z) && !previous.contains(.z) { z = origin.map { String($0.z) } ?? "" }
        }
    }

    private func reset() {
        let origin = store.snapshot?.origin
        x = origin.map { String($0.x) } ?? ""
        y = origin.map { String($0.y) } ?? ""
        z = origin.map { String($0.z) } ?? ""
    }
}
