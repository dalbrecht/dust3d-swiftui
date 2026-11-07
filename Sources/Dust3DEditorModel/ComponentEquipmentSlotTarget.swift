import Dust3DDocument
import Foundation

/// Captures the exact singleton selection and source revision for an equipment edit.
package struct ComponentEquipmentSlotTarget: Sendable {
    package let componentID: String
    private let context: CanvasAdjustmentTarget

    fileprivate init(snapshot: EditorSnapshot, componentID: String) {
        self.componentID = componentID
        context = CanvasAdjustmentTarget(snapshot: snapshot)
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        context.isCurrent(in: snapshot) && snapshot.equipmentSlotTarget?.componentID == componentID
    }
}

enum ComponentEquipmentSlotError: Error, Equatable, Sendable {
    case staleTarget
}

extension EditorSnapshot {
    package var equipmentSlotTarget: ComponentEquipmentSlotTarget? {
        guard let component = selectedComponent, let partID = component.partID,
            parts.first(where: { $0.id.utf8.elementsEqual(partID.utf8) })?.target == .model
        else { return nil }
        return ComponentEquipmentSlotTarget(snapshot: self, componentID: component.id)
    }
}
