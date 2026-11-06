import Foundation

/// Global stored-metadata clearing is independent of graph selection and geometry editability.
public struct BoneAssignmentClearTarget: Hashable, Sendable {
    private let context: CanvasAdjustmentTarget
    private let requestedNames: Set<Data>
    let edgeIDs: Set<String>
    /// Whether the original source contained at least one nonempty exact matching assignment.
    public var isAvailable: Bool { !edgeIDs.isEmpty }
    /// Number of stored matching edges, including locked/hidden/unsupported owners.
    public var matchingEdgeCount: Int { edgeIDs.count }

    /// Capture names and matching edges once; empty names never mean all unassigned edges.
    /// - Parameters: `snapshot` is the originating window; `names` are exact stored lookup identities.
    /// - Example: `BoneAssignmentClearTarget(snapshot: snapshot, names: ["Root"])`.
    public init(snapshot: EditorSnapshot, names: [String]) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        let requested = Set(names.filter { !$0.isEmpty }.map { Data($0.utf8) })
        requestedNames = requested
        edgeIDs = Set(snapshot.edges.filter { requested.contains(Data($0.boneName.utf8)) }.map(\.id))
    }

    /// Reject unavailable intent and any source, selection, constraint or window epoch change.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { isAvailable && context.isCurrent(in: snapshot) }
}

/// Clearing requires the captured window and original available stored matches.
public enum BoneAssignmentClearError: LocalizedError, Equatable, Sendable {
    case staleTarget
    public var errorDescription: String? {
        "The bone assignments are unavailable or have changed. Choose the bone again before clearing assignments."
    }
}
