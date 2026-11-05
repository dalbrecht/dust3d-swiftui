import Dust3DDocument
import Foundation

/// A rendered binding action belongs to one active group and its document/selection/constraint epochs.
public struct ComponentWrapBindingTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    let componentID: String?

    /// Capture the current singleton Skin/Cloth group; unavailable contexts never acquire a later selection.
    /// - Parameter snapshot: The originating window's immutable snapshot.
    /// - Example: `let target = ComponentWrapBindingTarget(snapshot: snapshot)`.
    public init(snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        if let component = snapshot.selectedComponent, component.isGroup,
            component.wrapping.mode == .skin || component.wrapping.mode == .cloth
        {
            componentID = component.id
        } else {
            componentID = nil
        }
    }
    /// Whether the original active group and all captured epochs still match.
    /// - Parameter snapshot: Current actor or UI snapshot from the same window.
    /// - Returns: False after replacement, edits/Undo, selection or constraint away-and-back.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        componentID != nil && context.isCurrent(in: snapshot) && snapshot.selectedComponentID == componentID
    }
}

/// A retained binding callback cannot mutate a later inspector or another window.
public enum ComponentWrapBindingError: Error, Equatable, Sendable { case staleTarget }

extension EditorState {
    /// Replace one captured group's binding atomically and advance geometry/source and material inputs.
    /// - Parameters: choice is an explicit authored replacement; target captures the originating active group.
    /// - Throws: Stale target, original document validation errors or cancellation without partial publication.
    /// - Example: `try state.editComponentWrapBinding(.group(bodyID), target: target)`.
    public mutating func editComponentWrapBinding(
        _ choice: ComponentWrapBindingChoice, target: ComponentWrapBindingTarget
    ) throws {
        try Task.checkCancellation()
        guard target.isCurrent(in: snapshot), let id = target.componentID else {
            throw ComponentWrapBindingError.staleTarget
        }
        var next = self
        try next.apply([.setComponentWrapBinding(id: id, choice: choice)])
        try Task.checkCancellation()
        self = next
    }
}
