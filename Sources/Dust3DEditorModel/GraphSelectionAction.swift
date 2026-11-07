import Foundation

/// Existing graph edits exposed through one captured contextual-action boundary.
public enum GraphSelectionAction: CaseIterable, Sendable, Hashable {
    case insertMidpoints
    case reverseEdges
    case reduceNodes
    case deleteSelection

    public var title: String {
        switch self {
        case .insertMidpoints: "Insert Midpoints on Selected Edges"
        case .reverseEdges: "Reverse Selected Edges"
        case .reduceNodes: "Reduce Selected Nodes"
        case .deleteSelection: "Delete Graph Selection"
        }
    }

    public var isDestructive: Bool { self == .deleteSelection }

    fileprivate func isAvailable(in snapshot: EditorSnapshot) -> Bool {
        switch self {
        case .insertMidpoints: snapshot.canInsertSelectedEdgeMidpoints
        case .reverseEdges: snapshot.canEditSelectedEdges
        case .reduceNodes: snapshot.canReduceSelectedNodes
        case .deleteSelection: snapshot.canDeleteSelection
        }
    }
}

public enum GraphSelectionActionError: Error, Equatable, Sendable, LocalizedError {
    case staleTarget
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .staleTarget: "The document, selection or editing constraints changed. Choose the action again."
        case .unavailable: "This graph action is unavailable for the captured selection."
        }
    }
}

/// Eligibility is captured before dispatch; unavailable actions cannot acquire
/// a later selection. Commands and identity allocation stay in the editing actor.
public struct GraphSelectionActionTarget: Sendable {
    public let action: GraphSelectionAction
    public let isAvailable: Bool
    private let context: CanvasAdjustmentTarget

    /// Capture the exact source and availability shown by a contextual menu.
    /// - Parameters:
    ///   - snapshot: Document, selection and constraint epochs at presentation.
    ///   - action: An existing batch graph command, without inferred hover targets.
    public init(snapshot: EditorSnapshot, action: GraphSelectionAction) {
        self.action = action
        isAvailable = action.isAvailable(in: snapshot)
        context = CanvasAdjustmentTarget(snapshot: snapshot)
    }

    /// Epoch admission is independent of initial eligibility; callers require both.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { context.isCurrent(in: snapshot) }
}
