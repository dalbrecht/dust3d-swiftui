import Dust3DDocument
import Foundation

/// Fresh command identities supplied by the session, or explicitly by deterministic pure-state callers.
public struct AddPlacementIdentities: Sendable {
    public let nodeID: String
    public let partID: String
    public let componentID: String
    public let edgeID: String

    /// Supply four distinct unused identities; a placement uses the subset required by its outcome.
    public init(nodeID: String, partID: String, componentID: String, edgeID: String) {
        self.nodeID = nodeID
        self.partID = partID
        self.componentID = componentID
        self.edgeID = edgeID
    }
}

struct AddPlacementTarget: Sendable {
    let contextID: UUID
    let documentIdentity: UUID
    let documentRevision: Int
    let selectionRevision: Int

    init(snapshot: EditorSnapshot, contextID: UUID) {
        self.contextID = contextID
        documentIdentity = snapshot.documentIdentity
        documentRevision = snapshot.documentRevision
        selectionRevision = snapshot.selectionRevision
    }

    func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && documentRevision == snapshot.documentRevision
            && selectionRevision == snapshot.selectionRevision
    }
}

/// The window's destination for independent new parts. Anchored placement keeps its existing owner.
package enum AddPlacementDestination: Equatable, Sendable {
    case selection
    case documentRoot
    case group(String)

    package static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.selection, .selection), (.documentRoot, .documentRoot): true
        case (.group(let left), .group(let right)): left.utf8.elementsEqual(right.utf8)
        default: false
        }
    }
}

extension EditorSnapshot {
    package func addPlacementGroup(_ id: String) -> ComponentTreeRow? {
        componentTree.rows.first { $0.id.utf8.elementsEqual(id.utf8) && $0.component.isGroup }
    }
}

/// One immutable click captured from a visible ghost; no pointer-motion work reaches the document actor.
public struct AddPlacementRequest: Sendable {
    let target: AddPlacementTarget
    public let position: NodePosition
    public let radius: Double
    public let anchorID: String?
    public let parentID: String?
    public let connectingTo: String?
    let lastAddedPosition: NodePosition?
    public var contextID: UUID { target.contextID }
}

/// A successful placement/connection or a deliberately suppressed duplicate click.
public enum AddPlacementOutcome: Equatable, Sendable {
    case placed(nodeID: String)
    case connected(edgeID: String)
    case duplicate
}

/// The accepted archive snapshot and transient chaining result for exactly one captured click.
public struct AddPlacementReceipt: Sendable {
    public let snapshot: EditorSnapshot
    public let outcome: AddPlacementOutcome
    public let contextID: UUID
    /// A rejected connection may fall through to node creation; retain its original validation diagnostic.
    public let connectionFallbackReason: String?
    public var nodeID: String? { if case .placed(let id) = outcome { id } else { nil } }
    public var didConnect: Bool { if case .connected = outcome { true } else { false } }
    public var didCommit: Bool { outcome != .duplicate }
}

/// Pure per-window Add-mode cursor state. Preview, radius and cancellation never mutate archive/history.
public struct AddPlacementState: Sendable {
    public private(set) var isActive = false
    public private(set) var anchorID: String?
    public private(set) var anchorPosition: NodePosition?
    public private(set) var ghostPosition: NodePosition?
    public private(set) var ghostPoint: CanvasPoint?
    public private(set) var sceneRadius: Double = 32
    public private(set) var projection: CanvasProjection?
    public private(set) var canvasHeight: Double = 0
    public var isVisible: Bool { isActive && ghostPosition != nil }
    /// Effective document radius for a visible click, distinct from the unbounded raw ghost preview.
    /// - Returns: Nil when hidden/inactive; otherwise the shared 0.001...1 commit conversion.
    public var wouldCommitRadius: Double? {
        guard isVisible else { return nil }
        return sceneRadius >= canvasHeight ? 1 : max(0.001, sceneRadius / canvasHeight)
    }
    private var target: AddPlacementTarget?
    private var parentID: String?
    private var hiddenCoordinate = 0.5
    private var anchorSceneRadius: Double?
    private var lastAddedPosition: NodePosition?
    private var lastDocumentIdentity: UUID?
    private var lastDocumentRevision: Int?

    public init() {}

    /// Enter with a frozen one-plane projection. A sole merged node of degree <2 anchors; otherwise create a part.
    /// - Parameters: `snapshot` captures document/selection; `canvasHeight` converts scene radius; nil parent derives the current group.
    /// - Throws: Invalid geometry/height or unsupported parent. Locks are deliberately absent from placement epochs.
    public mutating func begin(
        snapshot: EditorSnapshot, projection: CanvasProjection, canvasHeight: Double, parentID: String? = nil
    ) throws {
        try begin(
            snapshot: snapshot, projection: projection, canvasHeight: canvasHeight,
            destination: parentID.map(AddPlacementDestination.group) ?? .selection)
    }

    package mutating func begin(
        snapshot: EditorSnapshot, projection: CanvasProjection, canvasHeight: Double,
        destination: AddPlacementDestination
    ) throws {
        guard canvasHeight.isFinite, canvasHeight > 0 else { throw EditorError.invalidAddPlacement }
        // Validate the transform using a known bounded document point, not a possibly out-of-bounds canvas corner.
        let probe = NodePosition(x: 0.5, y: 0.5, z: 0.5)
        _ = try projection.position(at: projection.point(for: probe), hiddenCoordinate: 0.5)
        let merged = snapshot.transformNodes
        let candidate = merged.count == 1 ? merged.first : nil
        let anchor = candidate.flatMap { node in
            snapshot.edges.reduce(0) { $0 + ($1.fromID == node.id ? 1 : 0) + ($1.toID == node.id ? 1 : 0) } < 2
                ? node : nil
        }
        let parentID: String?
        switch destination {
        case .selection:
            parentID = snapshot.selectedComponent.flatMap { $0.isGroup ? $0.id : $0.parentID }
        case .documentRoot:
            parentID = nil
        case .group(let id):
            parentID = id
        }
        if anchor == nil, let parentID, snapshot.addPlacementGroup(parentID) == nil {
            throw DocumentError.invalidComponentStructure
        }
        let inherited = anchor.map { max(1, min(1, max(0.001, $0.value.radius)) * canvasHeight) }
        if lastDocumentIdentity != snapshot.documentIdentity || lastDocumentRevision != snapshot.documentRevision {
            lastAddedPosition = nil
        }
        lastDocumentIdentity = snapshot.documentIdentity
        lastDocumentRevision = snapshot.documentRevision
        self.projection = projection
        self.canvasHeight = canvasHeight
        self.parentID = anchor == nil ? parentID : nil
        anchorID = anchor?.id
        anchorPosition = anchor?.value.position
        anchorSceneRadius = inherited
        if let inherited { sceneRadius = inherited }
        hiddenCoordinate = Self.hiddenCoordinate(in: projection.plane, anchor: anchorPosition, origin: snapshot.origin)
        target = AddPlacementTarget(snapshot: snapshot, contextID: UUID())
        ghostPosition = nil
        ghostPoint = nil
        isActive = true
    }

    /// Wait for the new editing pane's geometry while retaining the current Add chain.
    public mutating func suspendProjectionForProfileChange() {
        guard isActive else { return }
        hideGhost()
        projection = nil
    }

    /// Attach a suspended Add chain to the new pane without carrying a click or pointer sample across.
    public mutating func reproject(
        snapshot: EditorSnapshot, projection: CanvasProjection, canvasHeight: Double
    ) throws {
        guard isActive, self.projection == nil, target?.isCurrent(in: snapshot) == true else {
            throw EditorError.staleAddPlacement
        }
        let radius = sceneRadius / self.canvasHeight * canvasHeight
        guard canvasHeight.isFinite, canvasHeight > 0, radius.isFinite, radius > 0 else {
            throw EditorError.invalidAddPlacement
        }
        let probe = NodePosition(x: 0.5, y: 0.5, z: 0.5)
        _ = try projection.position(at: projection.point(for: probe), hiddenCoordinate: 0.5)
        self.projection = projection
        self.canvasHeight = canvasHeight
        sceneRadius = radius
        anchorSceneRadius = anchorID == nil ? nil : radius
        hiddenCoordinate = Self.hiddenCoordinate(in: projection.plane, anchor: anchorPosition, origin: snapshot.origin)
        target = AddPlacementTarget(snapshot: snapshot, contextID: UUID())
    }

    private static func hiddenCoordinate(in plane: EditingPlane, anchor: NodePosition?, origin: NodePosition?)
        -> Double
    {
        switch plane {
        case .front: anchor?.z ?? origin?.z ?? 0.5
        case .side: anchor?.x ?? origin?.x ?? 0.5
        }
    }

    /// Update the visible ghost in constant time using the frozen projection and explicit hidden coordinate.
    /// - Parameter point: Absolute canvas coordinates. Invalid input leaves the prior ghost unchanged.
    public mutating func updatePointer(_ point: CanvasPoint) throws {
        guard isActive, let projection else { return }
        let position = try projection.position(at: point, hiddenCoordinate: hiddenCoordinate)
        if ghostPosition == nil, let anchorSceneRadius { sceneRadius = anchorSceneRadius }
        ghostPosition = position
        ghostPoint = point
    }

    /// Add scene points to a visible cursor radius, with no preview maximum.
    /// A transferred preview already below one point never grows when shrinking.
    /// - Throws: `invalidAddPlacement` for nonfinite input/arithmetic. Hidden/inactive cursors are unchanged.
    public mutating func adjustRadius(by delta: Double) throws {
        guard delta.isFinite else { throw EditorError.invalidAddPlacement }
        guard isVisible else { return }
        let proposed = sceneRadius + delta
        guard proposed.isFinite else { throw EditorError.invalidAddPlacement }
        sceneRadius = max(min(1, sceneRadius), proposed)
    }

    /// Hide preview geometry while retaining Add mode and the radius for its next visible cursor.
    public mutating func hideGhost() {
        ghostPosition = nil
        ghostPoint = nil
    }

    /// Return to Select without history; retain the cursor radius and duplicate bookkeeping for reentry.
    public mutating func cancel() {
        isActive = false
        hideGhost()
        anchorID = nil
        anchorPosition = nil
        projection = nil
        target = nil
        parentID = nil
        anchorSceneRadius = nil
    }

    /// Check document/selection epochs before using the cursor; geometry/plane changes cancel at the UI boundary.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { isActive && target?.isCurrent(in: snapshot) == true }

    /// Capture one click after the ghost becomes visible. Invalid connection candidates are revalidated by the actor.
    /// - Returns: Nil for an inactive/hidden ghost; committed radius clamps to 0.001...1 using actual canvas height.
    public func request(connectingTo: String? = nil) -> AddPlacementRequest? {
        guard let position = ghostPosition, let target, let radius = wouldCommitRadius else { return nil }
        return AddPlacementRequest(
            target: target, position: position, radius: radius, anchorID: anchorID,
            parentID: parentID, connectingTo: connectingTo, lastAddedPosition: lastAddedPosition)
    }

    /// Rebase chaining only for this still-active mode. Connections exit; duplicate receipts create no new anchor.
    /// - Throws: `staleAddPlacement` for cancelled/replaced contexts or an inconsistent receipt.
    public mutating func accept(_ receipt: AddPlacementReceipt) throws {
        guard isActive, let target, target.contextID == receipt.contextID,
            target.documentIdentity == receipt.snapshot.documentIdentity,
            receipt.snapshot.documentRevision >= target.documentRevision
        else { throw EditorError.staleAddPlacement }
        if receipt.didConnect {
            cancel()
            return
        }
        if let id = receipt.nodeID {
            guard let node = receipt.snapshot.nodes.first(where: { $0.id == id }) else {
                throw EditorError.staleAddPlacement
            }
            anchorID = id
            anchorPosition = node.value.position
            anchorSceneRadius = max(1, node.value.radius * canvasHeight)
            lastAddedPosition = node.value.position
            parentID = nil
        }
        lastDocumentRevision = receipt.snapshot.documentRevision
        self.target = AddPlacementTarget(snapshot: receipt.snapshot, contextID: receipt.contextID)
    }
}
