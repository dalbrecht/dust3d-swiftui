import Dust3DDocument
import Foundation

/// Captures the exact singleton selection and source revision for an equipment edit.
package struct ComponentEquipmentSlotTarget: Sendable {
    private enum Scope: Sendable {
        case component(CanvasAdjustmentTarget)
        case graph(GraphModelPartTarget)
    }

    package let componentID: String
    private let scope: Scope

    fileprivate init(snapshot: EditorSnapshot, componentID: String) {
        self.componentID = componentID
        scope = .component(CanvasAdjustmentTarget(snapshot: snapshot))
    }

    package init?(graphTarget: GraphModelPartTarget) {
        guard let component = graphTarget.component else { return nil }
        componentID = component.id
        scope = .graph(graphTarget)
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        switch scope {
        case .component(let context):
            return context.isCurrent(in: snapshot)
                && snapshot.equipmentSlotTarget?.componentID.utf8.elementsEqual(componentID.utf8) == true
        case .graph(let target):
            return target.isCurrent(in: snapshot)
        }
    }
}

enum ComponentEquipmentSlotError: Error, Equatable, Sendable {
    case staleTarget
}

extension GraphModelPartTarget {
    package var equipmentSlotTarget: ComponentEquipmentSlotTarget? {
        ComponentEquipmentSlotTarget(graphTarget: self)
    }
}

extension EditorSnapshot {
    package var equipmentSlotTarget: ComponentEquipmentSlotTarget? {
        guard let component = selectedComponent, let partID = component.partID,
            parts.first(where: { $0.id.utf8.elementsEqual(partID.utf8) })?.target == .model
        else { return nil }
        return ComponentEquipmentSlotTarget(snapshot: self, componentID: component.id)
    }
}
