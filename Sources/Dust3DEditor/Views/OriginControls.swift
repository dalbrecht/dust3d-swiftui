import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct OriginControls: View {
    let store: EditorStore
    @State private var draft = OriginInspectorDraft()

    var body: some View {
        let source = store.originInspectorSource
        let apply = source.flatMap { store.originInspectorApplyAction(source: $0) }
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
                    TextField("Origin X", text: $draft.x).accessibilityIdentifier("origin-x")
                        .disabled(store.locks.contains(.x))
                        .focusedValue(\.editorTextEditing, true)
                }
                HStack {
                    Text("Y").frame(width: 12)
                    TextField("Origin Y", text: $draft.y).accessibilityIdentifier("origin-y")
                        .disabled(store.locks.contains(.y))
                        .focusedValue(\.editorTextEditing, true)
                }
                HStack {
                    Text("Z").frame(width: 12)
                    TextField("Origin Z", text: $draft.z).accessibilityIdentifier("origin-z")
                        .disabled(store.locks.contains(.z))
                        .focusedValue(\.editorTextEditing, true)
                }
                HStack {
                    Button("Reset Draft") {
                        if let source, store.originInspectorSource == source { draft.reset(for: source) }
                    }
                    Spacer()
                    Button("Apply Origin") {
                        guard draft.source == source else { return }
                        apply?(draft.x, draft.y, draft.z)
                    }
                    .disabled(apply == nil)
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
        .disabled(store.isWorking || source == nil || draft.source != source)
        .onChange(of: source, initial: true) { _, current in draft.synchronize(to: current) }
        .onChange(of: store.locks) { previous, current in
            guard draft.source == source else { return }
            let origin = source?.origin
            if current.contains(.x) && !previous.contains(.x) { draft.x = origin.map { String($0.x) } ?? "" }
            if current.contains(.y) && !previous.contains(.y) { draft.y = origin.map { String($0.y) } ?? "" }
            if current.contains(.z) && !previous.contains(.z) { draft.z = origin.map { String($0.z) } ?? "" }
        }
    }
}

struct OriginInspectorSource: Equatable {
    let documentIdentity: UUID
    let origin: NodePosition?
}

struct OriginInspectorDraft {
    private(set) var source: OriginInspectorSource?
    var x = ""
    var y = ""
    var z = ""

    mutating func synchronize(to source: OriginInspectorSource?) {
        guard self.source != source else { return }
        self.source = source
        seed(from: source?.origin)
    }

    mutating func reset(for source: OriginInspectorSource) {
        guard self.source == source else { return }
        seed(from: source.origin)
    }

    private mutating func seed(from origin: NodePosition?) {
        x = origin.map { String($0.x) } ?? ""
        y = origin.map { String($0.y) } ?? ""
        z = origin.map { String($0.z) } ?? ""
    }
}
