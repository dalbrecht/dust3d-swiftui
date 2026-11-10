import Dust3DDocument
import Foundation

/// One explicit candidate whose part settings can own a two-node connection.
public struct NodeConnectionOwner: Identifiable, Sendable {
    public let nodeID: String
    public let nodeTitle: String
    public let partID: String
    public let partTitle: String
    /// Preserve exact source spelling in native menu identity.
    public var id: Data { Data(nodeID.utf8) }
}

/// A two-endpoint connection belongs to one document, selection and constraint epoch.
public struct NodeConnectionTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    /// Eligible endpoints in document order, never Set iteration order. Empty means unavailable.
    public let owners: [NodeConnectionOwner]
    /// Joining different parts consumes one part's settings; the user chooses the surviving owner.
    public var requiresOwnershipChoice: Bool {
        owners.count == 2 && !owners[0].partID.utf8.elementsEqual(owners[1].partID.utf8)
    }

    /// Capture cheap metadata eligibility without parsing XML or invoking the engine on the UI actor.
    /// The document command retains complete chain/profile validation and atomic error behavior.
    public init(snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        owners = Self.eligibleOwners(snapshot)
    }

    /// Whether the exact captured document, revision, selection and constraints still match.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        owners.count == 2 && context.isCurrent(in: snapshot)
    }

    private static func eligibleOwners(_ snapshot: EditorSnapshot) -> [NodeConnectionOwner] {
        guard snapshot.selectedIDs.count == 2, snapshot.selectedEdgeIDs.isEmpty,
            snapshot.selectedComponentIDs.isEmpty, snapshot.selectedPartID == nil,
            snapshot.edges.count < 20_000
        else { return [] }
        let endpoints = snapshot.nodes.filter { node in
            snapshot.selectedIDs.contains { $0.utf8.elementsEqual(node.id.utf8) }
        }
        guard endpoints.count == 2,
            endpoints.allSatisfy({ $0.isEditable && !$0.id.isEmpty && $0.partID?.isEmpty == false })
        else { return [] }
        var degree = [0, 0]
        for edge in snapshot.edges {
            let from = endpoints.firstIndex { $0.id.utf8.elementsEqual(edge.fromID.utf8) }
            let to = endpoints.firstIndex { $0.id.utf8.elementsEqual(edge.toID.utf8) }
            if let from { degree[from] += 1 }
            if let to { degree[to] += 1 }
            if degree.contains(where: { $0 >= 2 }) || (from != nil && to != nil) { return [] }
        }
        var result: [NodeConnectionOwner] = []
        for node in endpoints {
            guard let partID = node.partID,
                let part = snapshot.parts.first(where: { $0.id.utf8.elementsEqual(partID.utf8) })
            else { return [] }
            result.append(.init(nodeID: node.id, nodeTitle: node.title, partID: partID, partTitle: part.title))
        }
        return result
    }
}

/// Retained unavailable, replaced or differently owned connection intent cannot retarget current selection.
public enum NodeConnectionSelectionError: LocalizedError, Equatable, Sendable {
    case staleTarget
    public var errorDescription: String? {
        "The connection selection changed. Select two endpoints and choose Connect again."
    }
}

extension EditorState {
    /// Connect the captured endpoints as one atomic Undo step using an explicitly selected settings owner.
    /// - Parameters: `target` captures source/selection epochs; `ownerID` is an exact captured endpoint;
    ///   `edgeID` is a fresh caller-supplied edge identity for deterministic state commands.
    /// - Throws: Stale intent, cancellation or the original document validation error, without publication.
    public mutating func connectSelectedNodes(target: NodeConnectionTarget, ownerID: String, edgeID: String) throws {
        try connectSelectedNodes(target: target, ownerID: ownerID, edgeID: edgeID, splitIdentities: nil)
    }

    mutating func connectSelectedNodes(
        target: NodeConnectionTarget, ownerID: String, edgeID: String,
        splitIdentities: ((PartSplitRequirement) -> [PartSplitIdentity])?
    ) throws {
        try Task.checkCancellation()
        let current = snapshot
        guard target.isCurrent(in: current),
            let owner = target.owners.firstIndex(where: { $0.nodeID.utf8.elementsEqual(ownerID.utf8) })
        else { throw NodeConnectionSelectionError.staleTarget }
        var next = self
        let from = target.owners[owner].nodeID
        let to = target.owners[1 - owner].nodeID
        do {
            try next.apply([.joinNodes(id: edgeID, from: from, to: to)])
        } catch DocumentError.invalidNode {
            guard let splitIdentities, !target.requiresOwnershipChoice,
                let repair = try current.document.legacyIslandConnectionRepair(id: edgeID, from: from, to: to)
            else { throw DocumentError.invalidNode }
            try next.apply([
                repair.edge, .splitPart(id: repair.split.partID, identities: splitIdentities(repair.split)),
            ])
        }
        try Task.checkCancellation()
        self = next
    }
}
