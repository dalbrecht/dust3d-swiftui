import Dust3DDocument
import SwiftUI

struct ComponentInspector: View {
    let store: EditorStore
    let component: DocumentComponent
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Component inspector").font(.title3)
            Text(component.id).font(.caption).textSelection(.enabled)
                .id(component.id)
                .focusedValue(\.editorTextEditing, true)
            TextField("Component name", text: $name)
                .accessibilityIdentifier("component-name")
                .focusedValue(\.editorTextEditing, true)
                .onSubmit { store.renameComponent(component.id, name: name) }
            HStack {
                Button("Reset Name") { name = component.name }
                Spacer()
                Button("Apply Name") { store.renameComponent(component.id, name: name) }
            }
            Picker(
                "Combine mode",
                selection: Binding<ComponentCombineMode?>(
                    get: { component.combineMode },
                    set: { if let mode = $0 { store.setComponentCombineMode(component.id, mode: mode) } })
            ) {
                if component.combineMode == nil {
                    Text("Unsupported source mode").tag(nil as ComponentCombineMode?)
                }
                ForEach(ComponentCombineMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(Optional(mode))
                }
            }
            .accessibilityIdentifier("component-combine-mode")
            .help(
                "Normal unions, Inversion subtracts, and Uncombined retains separate geometry. Order matters. One undo step."
            )
            ComponentSmoothingControls(store: store, component: component)
            ComponentOrderMenu(store: store)
            ComponentReparentControls(store: store, componentID: component.id)
            if let parent = component.parentID {
                Text("Parent: \(parent)").font(.caption).textSelection(.enabled)
                    // Recreate the native selectable text when its identity changes; AppKit otherwise retains its old AX text.
                    .id(parent)
                    .focusedValue(\.editorTextEditing, true)
            }
            Text("\(component.childIDs.count) child components").font(.caption).foregroundStyle(.secondary)
            if let partID = component.partID, store.snapshot?.parts.contains(where: { $0.id == partID }) == true {
                Button("Inspect Linked Part") { store.selectPart(partID) }
            } else if let kind = component.linkDataType {
                Text("Link: \(kind) · \(component.linkData ?? "")").font(.caption).textSelection(.enabled)
                    .focusedValue(\.editorTextEditing, true)
            }
            Text(
                "Component names are independent of part names. Renaming is one undo step; tree selection does not change the document."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(store.isWorking)
        .onChange(of: component.id, initial: true) { _, _ in name = component.name }
        .onChange(of: component.name) { _, value in name = value }
    }
}
