import Dust3DDocument
import SwiftUI

struct PartInspector: View {
    let store: EditorStore
    let part: DocumentPart
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Part inspector").font(.title3)
            Text(part.id).font(.caption).textSelection(.enabled)
                .focusedValue(\.editorTextEditing, true)
            TextField("Part name", text: $name)
                .accessibilityIdentifier("part-name")
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { store.renamePart(part.id, name: name) }
            HStack {
                Button("Reset Name") { name = part.name }
                Spacer()
                Button("Apply Name") { store.renamePart(part.id, name: name) }
            }
            Toggle("Visible in canvas", isOn: state(.visible, value: part.isVisible))
            Toggle("Locked", isOn: state(.locked, value: part.isLocked))
            Toggle("Disabled in mesh", isOn: state(.disabled, value: part.isDisabled))
            Button("Select Part Nodes") {
                store.select(Set((store.snapshot?.nodes ?? []).filter { $0.partID == part.id }.map(\.id)))
            }
            .disabled(store.snapshot?.nodes.contains(where: { $0.partID == part.id }) != true)
            Text(
                "Visibility hides editing overlays. Disabled parts are excluded from the mesh. These controls remain available to restore hidden, locked or disabled parts. Each change is one undo step."
            )
            .font(.caption).foregroundStyle(.secondary)
            PartModifierControls(store: store, part: part)
            Text("Part names are independent of component names.").font(.caption).foregroundStyle(.secondary)
        }
        .disabled(store.isWorking)
        .onChange(of: part.id, initial: true) { _, _ in name = part.name }
        .onChange(of: part.name) { _, value in name = value }
    }

    private func state(_ property: PartStateProperty, value: Bool) -> Binding<Bool> {
        Binding(get: { value }, set: { store.setPartState(part.id, property: property, value: $0) })
    }
}
