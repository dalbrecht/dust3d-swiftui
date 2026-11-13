import Dust3DDocument
import SwiftUI

struct ComponentInspector: View {
    let store: EditorStore
    let component: DocumentComponent
    var body: some View {
        let snapshot = store.snapshot
        let equipment = snapshot?.equipmentSlotTarget.flatMap { target in
            target.componentID.utf8.elementsEqual(component.id.utf8) ? target : nil
        }
        let base = equipment.flatMap { _ in component.equipmentRenameBaseName }
        let apply = store.inspectedComponentNameAction(component, equipment: base == nil ? nil : equipment)
        VStack(alignment: .leading, spacing: 16) {
            Text("Component inspector").font(.title3)
            Text(component.id).font(.caption).textSelection(.enabled)
                .id(component.id)
                .focusedValue(\.editorTextEditing, true)
            ComponentNameFields(
                name: base ?? component.name, title: base == nil ? "Component name" : "Component base name",
                apply: apply
            )
            .id([
                Data((snapshot?.documentIdentity.uuidString ?? "").utf8), Data(component.id.utf8),
                Data(component.name.utf8), Data([base == nil ? 0 : 1]),
            ])
            if let snapshot, let equipment {
                ComponentEquipmentSlotControls(store: store, component: component, target: equipment)
                    .id(snapshot.documentIdentity)
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
            ComponentColorControls(store: store, component: component)
            ComponentColorImageControls(store: store, component: component)
            if store.snapshot?.showsComponentSmoothing(for: [component]) == true {
                ComponentSmoothingControls(store: store, component: component)
            }
            if component.isGroup {
                ComponentWrappingControls(store: store, component: component)
                ComponentStitchingControls(store: store, component: component)
            }
            CanvasPartIsolationControls(store: store, componentID: component.id)
            ComponentOrderMenu(store: store)
            if let parent = component.parentID {
                Text("Parent: \(parent)").font(.caption).textSelection(.enabled)
                    // Recreate the native selectable text when its identity changes; AppKit otherwise retains its old AX text.
                    .id(parent)
                    .focusedValue(\.editorTextEditing, true)
            }
            Text("\(component.childIDs.count) child components").font(.caption).foregroundStyle(.secondary)
            if let partID = component.partID,
                let part = store.snapshot?.parts.first(where: { $0.id.utf8.elementsEqual(partID.utf8) })
            {
                if part.target == .cutFace {
                    CutFaceReferenceCountLabel(count: part.cutFaceReferenceCount)
                }
                PartMirrorControls(store: store)
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
    }
}

private struct ComponentNameFields: View {
    let name: String
    let title: LocalizedStringKey
    let apply: (@MainActor (String) -> Void)?
    @State private var draft = ""

    var body: some View {
        TextField(title, text: $draft)
            .accessibilityIdentifier("component-name")
            .focusedValue(\.editorTextEditing, true)
            .onSubmit { apply?(draft) }
            .onChange(of: name, initial: true) { _, value in draft = value }
        HStack {
            Button("Reset Name") { draft = name }
            Spacer()
            Button("Apply Name") { apply?(draft) }.disabled(apply == nil)
        }
    }
}
