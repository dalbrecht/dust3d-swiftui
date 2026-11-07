import Dust3DDocument
import Dust3DEditorModel
import Foundation
import SwiftUI

struct ComponentEquipmentSlotControls: View {
    let store: EditorStore
    let component: DocumentComponent
    let target: ComponentEquipmentSlotTarget
    @State private var draft = ""

    private var hasChange: Bool {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return component.equipmentSlot != nil }
        return component.equipmentSlot?.utf8.elementsEqual(value.utf8) != true
    }

    var body: some View {
        GroupBox("Equipment") {
            HStack {
                TextField("Equipment Slot", text: $draft, prompt: Text("armor/2"))
                    .accessibilityIdentifier("component-equipment-slot")
                    .accessibilityHint("Leave blank to clear the equipment slot.")
                    .focusedValue(\.editorTextEditing, true)
                    .onSubmit(apply)
                Button("Apply Slot", action: apply)
                    .disabled(!hasChange)
            }
        }
        .onChange(of: component.id, initial: true) { _, _ in draft = component.equipmentSlot ?? "" }
        .onChange(of: component.equipmentSlot.map { Data($0.utf8) }) { _, _ in
            draft = component.equipmentSlot ?? ""
        }
    }

    private func apply() {
        guard hasChange else { return }
        store.setComponentEquipmentSlot(draft, target: target)
    }
}
