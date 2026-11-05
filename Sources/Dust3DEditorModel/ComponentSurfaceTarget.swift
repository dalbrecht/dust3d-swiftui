import Dust3DDocument
import Foundation

/// One typed finish edit; only the requested attribute changes.
public enum ComponentSurfaceEdit: Sendable {
    case pattern(ComponentSurfacePattern)
    case scalar(ComponentSurfaceScalar, Double)
    case ink(DocumentColor?)

    func command(componentID: String) -> DocumentCommand {
        switch self {
        case .pattern(let value): return .setComponentSurfacePattern(id: componentID, pattern: value)
        case .scalar(let property, let value):
            return .setComponentSurfaceScalar(id: componentID, property: property, value: value)
        case .ink(let value): return .setComponentSurfaceColor(id: componentID, color: value)
        }
    }
}

/// Immutable admission for one active group, including source, selection and constraint epochs.
public struct ComponentSurfaceTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    let componentID: String?

    /// Capture the rendered inspector before a draft/apply callback can be retained.
    /// - Parameter snapshot: The originating window state; unavailable selections never acquire a later target.
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

    /// Reject stale documents, Undo, selection/lock away-and-back, and unavailable source modes.
    /// - Parameter snapshot: Current actor or UI snapshot.
    /// - Returns: True only for the original active singleton group.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        componentID != nil && context.isCurrent(in: snapshot) && snapshot.selectedComponentID == componentID
    }
}

/// A stale finish callback cannot mutate whichever component later becomes selected.
public enum ComponentSurfaceError: Error, Equatable, Sendable { case staleTarget }

extension EditorState {
    /// Stage a field-local finish edit and check cancellation before publication.
    /// - Parameters: edit is the typed requested replacement; target captures the original inspector epoch.
    /// - Throws: Stale target, original document validation errors or cancellation without partial state.
    /// - Example: `try state.editComponentSurface(.pattern(.spots), target: target)`.
    public mutating func editComponentSurface(_ edit: ComponentSurfaceEdit, target: ComponentSurfaceTarget) throws {
        guard target.isCurrent(in: snapshot), let id = target.componentID else {
            throw ComponentSurfaceError.staleTarget
        }
        var next = self
        try next.apply([edit.command(componentID: id)])
        try Task.checkCancellation()
        self = next
    }
}
