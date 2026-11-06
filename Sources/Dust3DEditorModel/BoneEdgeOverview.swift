import Dust3DDocument
import Foundation

/// Exact stored-name grouping or Qt's non-CutFace unassigned population.
public enum BoneEdgeScope: Sendable {
    case named(String)
    case unassigned
}

private struct BoneEdgeMatchGroup: Sendable {
    var matching = Set<String>()
    var selectable = Set<String>()
}

/// Counts and grouping are prepared once from an immutable snapshot, without XML or engine work.
public struct BoneEdgeOverview: Sendable {
    /// All edges except those with a resolved CutFace owner, including read-only and unresolved owners.
    public let totalEdgeCount: Int
    /// Nonempty stored names in the progress population, including unsupported names.
    public let assignedEdgeCount: Int
    /// Unassigned stored edges in the progress population, regardless of selectability.
    public var unassignedEdgeCount: Int { totalEdgeCount - assignedEdgeCount }
    private let context: CanvasAdjustmentTarget
    private let named: [Data: BoneEdgeMatchGroup]
    private let unassigned: BoneEdgeMatchGroup

    /// Preserve raw match counts separately from native graph selection eligibility.
    /// - Parameter snapshot: The originating window and its parsed metadata.
    public init(snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        let parts = Dictionary(snapshot.parts.map { (Data($0.id.utf8), $0) }, uniquingKeysWith: { first, _ in first })
        let editableParts = Set(snapshot.parts.filter(\.isEditable).map { Data($0.id.utf8) })
        let editableNodes = Set(
            snapshot.nodes.filter {
                $0.isEditable && ($0.partID.map { parts[Data($0.utf8)] != nil } ?? true)
            }.map { Data($0.id.utf8) })
        var total = 0
        var assigned = 0
        var groups: [Data: BoneEdgeMatchGroup] = [:]
        var empty = BoneEdgeMatchGroup()
        for edge in snapshot.edges {
            let cutFace = edge.partID.flatMap { parts[Data($0.utf8)] }?.target == .cutFace
            if !cutFace {
                total += 1
                if !edge.boneName.isEmpty { assigned += 1 }
            }
            let selectable =
                edge.partID.map { editableParts.contains(Data($0.utf8)) } == true
                && editableNodes.contains(Data(edge.fromID.utf8)) && editableNodes.contains(Data(edge.toID.utf8))
            if !edge.boneName.isEmpty {
                let key = Data(edge.boneName.utf8)
                groups[key, default: BoneEdgeMatchGroup()].matching.insert(edge.id)
                if selectable { groups[key, default: BoneEdgeMatchGroup()].selectable.insert(edge.id) }
            } else if !cutFace {
                empty.matching.insert(edge.id)
                if selectable { empty.selectable.insert(edge.id) }
            }
        }
        totalEdgeCount = total
        assignedEdgeCount = assigned
        named = groups
        unassigned = empty
    }

    /// Freeze one action and its raw highlights. A nonempty name with zero eligible matches
    /// remains selectable so the explicit action clears graph selection as Qt does.
    /// - Parameter scope: Exact name or non-CutFace unassigned edges.
    public func target(for scope: BoneEdgeScope) -> BoneEdgeSelectionTarget {
        switch scope {
        case .unassigned:
            return .init(context: context, key: nil, group: unassigned, available: !unassigned.matching.isEmpty)
        case .named(let name):
            let key = Data(name.utf8)
            return .init(
                context: context, key: key, group: named[key] ?? BoneEdgeMatchGroup(), available: !name.isEmpty)
        }
    }
}

/// Immutable source-correlated matching IDs; initially unavailable intent never acquires later matches.
public struct BoneEdgeSelectionTarget: Hashable, Sendable {
    private let context: CanvasAdjustmentTarget
    private let scopeKey: Data?
    /// Raw exact matches for transient highlights; visibility is applied by the canvas.
    public let matchingEdgeIDs: Set<String>
    let selectableEdgeIDs: Set<String>
    /// Initial intent admission; a nonempty named group may intentionally have zero matches.
    public let isAvailable: Bool
    /// Eligible edges an explicit action will select; raw highlights can include more matches.
    public var selectableEdgeCount: Int { selectableEdgeIDs.count }

    fileprivate init(context: CanvasAdjustmentTarget, key: Data?, group: BoneEdgeMatchGroup, available: Bool) {
        self.context = context
        scopeKey = key
        matchingEdgeIDs = group.matching
        selectableEdgeIDs = group.selectable
        isAvailable = available
    }

    /// Require the original window/source and every selection/constraint epoch, including ABA and Undo.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { isAvailable && context.isCurrent(in: snapshot) }
}

/// Selection intent must remain bound to its originally available source and interaction epochs.
public enum BoneEdgeSelectionError: LocalizedError, Equatable, Sendable {
    case staleTarget
    public var errorDescription: String? {
        "The bone edge group is unavailable or has changed. Choose the group again before selecting edges."
    }
}
