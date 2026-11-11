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
            if let snapshot = store.snapshot, let target = snapshot.equipmentSlotTarget,
                target.componentID == component.id
            {
                ComponentEquipmentSlotControls(store: store, component: component, target: target)
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
                if let snapshot = store.snapshot {
                    let support = ComponentStitchingBatchSupport(
                        groups: [component], components: snapshot.componentTree.rows.map(\.component),
                        parts: snapshot.parts)
                    if support.back {
                        ComponentStitchingControls(store: store, component: component, support: support)
                    }
                }
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
        .onChange(of: component.id, initial: true) { _, _ in name = component.name }
        .onChange(of: component.name) { _, value in name = value }
    }
}
