import Dust3DDocument
import Foundation

/// Explicit identities from an inspector render, never a later current-selection lookup.
public enum GraphInspectorAction: Sendable {
    case connect(from: String, to: String)
    case deleteNode(id: String)
    case reverseEdge(id: String)
    case disconnectEdge(id: String)
    case selectEndpoints(edgeID: String)
    /// Replace transient graph selection using this selected edge’s exact stored bone assignment.
    case selectBoneEdges(edgeID: String)
    case insertMidpoint(edgeID: String)
}

/// Frozen eligibility and source epochs for one contextual action.
public struct GraphInspectorActionTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    let action: GraphInspectorAction?
    let boneEdgeIDs: Set<String>

    fileprivate init(context: CanvasAdjustmentTarget, action: GraphInspectorAction?, boneEdgeIDs: Set<String> = []) {
        self.context = context
        self.action = action
        self.boneEdgeIDs = boneEdgeIDs
    }
    /// Endpoint and bone-group selection are transient; all other available actions edit history.
    public var changesDocument: Bool {
        switch action {
        case .none, .selectEndpoints, .selectBoneEdges: false
        default: true
        }
    }
    /// Reject replacement, edit/Undo, selection/constraint ABA and initially unavailable intent.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        action != nil && context.isCurrent(in: snapshot)
    }
}

/// Build the metadata index once per inspector render; each menu row captures a constant-time target.
public struct GraphInspectorActionContext: Sendable {
    private let context: CanvasAdjustmentTarget
    private let availability: Availability

    private struct Availability: Sendable {
        var node: Data?
        var deletableNode: Data?
        var peers = Set<Data>()
        var mutableEdges = Set<Data>()
        var selectableEdge: Data?
        var midpointEdge: Data?
        var boneAnchor: Data?
        var boneEdgeIDs = Set<String>()
    }

    /// No XML parsing, engine access or actor mutation occurs while constructing inspector controls.
    public init(snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        availability = Self.index(snapshot)
    }

    /// Capture the actual row identities and their initial availability; unavailable rows never acquire later intent.
    public func target(for action: GraphInspectorAction) -> GraphInspectorActionTarget {
        let valid: Bool
        var boneEdgeIDs = Set<String>()
        switch action {
        case .connect(let from, let to):
            valid = availability.node == Data(from.utf8) && availability.peers.contains(Data(to.utf8))
        case .deleteNode(let id): valid = availability.deletableNode == Data(id.utf8)
        case .reverseEdge(let id), .disconnectEdge(let id): valid = availability.mutableEdges.contains(Data(id.utf8))
        case .selectEndpoints(let id): valid = availability.selectableEdge == Data(id.utf8)
        case .selectBoneEdges(let id):
            valid = availability.boneAnchor == Data(id.utf8)
            if valid { boneEdgeIDs = availability.boneEdgeIDs }
        case .insertMidpoint(let id): valid = availability.midpointEdge == Data(id.utf8)
        }
        return .init(context: context, action: valid ? action : nil, boneEdgeIDs: boneEdgeIDs)
    }

    private static func index(_ snapshot: EditorSnapshot) -> Availability {
        var result = Availability()
        guard snapshot.selectedComponentIDs.isEmpty, snapshot.selectedPartID == nil else { return result }
        let nodeScope = snapshot.selectedIDs.count == 1 && snapshot.selectedEdgeIDs.isEmpty
        let edgeScope = snapshot.selectedIDs.isEmpty && snapshot.selectedEdgeIDs.count == 1
        guard nodeScope || edgeScope else { return result }
        let partIDs = Set(snapshot.parts.map { Data($0.id.utf8) })
        let allNodes = Set(snapshot.nodes.map { Data($0.id.utf8) })
        let editableNodes = Set(
            snapshot.nodes.filter { node in
                node.isEditable && (node.partID.map { partIDs.contains(Data($0.utf8)) } ?? true)
            }.map { Data($0.id.utf8) })
        if nodeScope, let selected = snapshot.selectedIDs.first,
            let node = snapshot.nodes.first(where: { $0.id.utf8.elementsEqual(selected.utf8) })
        {
            let key = Data(node.id.utf8)
            result.node = key
            if editableNodes.contains(key) { result.deletableNode = key }
            if editableNodes.contains(key), node.partID != nil {
                result.peers = Set(
                    snapshot.connectionTargets.filter {
                        editableNodes.contains(Data($0.id.utf8)) && $0.partID != nil
                    }.map { Data($0.id.utf8) })
            }
            for edge in snapshot.edges {
                let from = Data(edge.fromID.utf8)
                let to = Data(edge.toID.utf8)
                if (from == key || to == key) && editableNodes.contains(from) && editableNodes.contains(to) {
                    result.mutableEdges.insert(Data(edge.id.utf8))
                }
            }
        } else if edgeScope, let selected = snapshot.selectedEdgeIDs.first,
            let edge = snapshot.edges.first(where: { $0.id.utf8.elementsEqual(selected.utf8) })
        {
            let key = Data(edge.id.utf8)
            let from = Data(edge.fromID.utf8)
            let to = Data(edge.toID.utf8)
            if allNodes.contains(from) && allNodes.contains(to) { result.selectableEdge = key }
            if editableNodes.contains(from) && editableNodes.contains(to) { result.mutableEdges.insert(key) }
            if result.mutableEdges.contains(key) && snapshot.canInsertSelectedEdgeMidpoint { result.midpointEdge = key }
            if !edge.boneName.isEmpty {
                let editableParts = Set(snapshot.parts.filter(\.isEditable).map { Data($0.id.utf8) })
                for candidate in snapshot.edges where candidate.hasExactBoneName(edge.boneName) {
                    guard let owner = candidate.partID, editableParts.contains(Data(owner.utf8)),
                        editableNodes.contains(Data(candidate.fromID.utf8)),
                        editableNodes.contains(Data(candidate.toID.utf8))
                    else { continue }
                    result.boneEdgeIDs.insert(candidate.id)
                }
                result.boneAnchor = key
            }
        }
        return result
    }
}

/// A contextual inspector action cannot be applied to different source or interaction intent.
public enum GraphInspectorActionError: LocalizedError, Equatable, Sendable {
    case staleTarget
    public var errorDescription: String? {
        "The inspector target changed. Select the item and choose the action again."
    }
}
