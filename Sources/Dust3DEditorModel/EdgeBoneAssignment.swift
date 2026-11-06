import Dust3DDocument
import Foundation

/// Frozen explicit-edge assignment and source epochs, including initially unavailable intent.
public struct EdgeBoneAssignmentTarget: Hashable, Sendable {
    private let context: CanvasAdjustmentTarget
    private let requestedIDs: Set<Data>
    private let names: [BoneNameIdentity]
    let edgeIDs: Set<String>
    /// Initial admission only; use isCurrent(in:) before dispatching against a live snapshot.
    public let isAvailable: Bool
    /// Number of exact resolved edges represented by the controls.
    public var selectedCount: Int { names.count }
    /// Nil denotes mixed names or no resolved edges; byte-distinct spellings remain distinct.
    public var commonName: BoneNameIdentity? {
        guard let first = names.first, names.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// Capture selected edges, optionally requiring a particular inspector row's exact identities.
    /// - Parameters: `snapshot` is the source window; `edgeIDs` must equal its explicit selected edge set.
    /// - Example: `EdgeBoneAssignmentTarget(snapshot: snapshot, edgeIDs: [edge.id])`.
    public init(snapshot: EditorSnapshot, edgeIDs: Set<String>? = nil) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        let requested = Set((edgeIDs ?? snapshot.selectedEdgeIDs).map { Data($0.utf8) })
        requestedIDs = requested
        let rows = snapshot.edges.filter { requested.contains(Data($0.id.utf8)) }
        self.edgeIDs = Set(rows.map(\.id))
        names = rows.map { BoneNameIdentity($0.boneName) }
        let eligible = EdgeBoneAssignmentEligibility.edgeIDs(
            nodes: snapshot.nodes, edges: snapshot.edges, parts: snapshot.parts)
        isAvailable =
            !requested.isEmpty && requested == Set(snapshot.selectedEdgeIDs.map { Data($0.utf8) })
            && rows.count == requested.count && requested.isSubset(of: eligible)
            && snapshot.selectedPartID == nil && snapshot.selectedComponentIDs.isEmpty
    }

    /// Require the original window, source, selection and constraints, even after ABA or Undo.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { isAvailable && context.isCurrent(in: snapshot) }
    /// Whether an explicit new value changes any captured name; validation errors remain document errors.
    public func hasChanges(name: String) -> Bool { isAvailable && names.contains { $0 != BoneNameIdentity(name) } }

    // All names are derived from the immutable source epoch and requested byte identities.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.context == rhs.context && lhs.requestedIDs == rhs.requestedIDs && lhs.isAvailable == rhs.isAvailable
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(context)
        hasher.combine(requestedIDs)
        hasher.combine(isAvailable)
    }
}

/// Mixed blank presentation is not an implicit clear; only an actual text change enables submission.
public struct EdgeBoneNameDraft: Sendable {
    /// Source intent captured when this draft was created or reset by its view.
    public let target: EdgeBoneAssignmentTarget
    /// Current exact text; mixed assignments begin with a blank presentation.
    public private(set) var value: BoneNameIdentity
    private var edited = false
    /// True only after an actual text change that differs from at least one captured assignment.
    public var canSubmit: Bool { edited && target.hasChanges(name: value.rawValue) }
    /// Initialize from common text or an unedited mixed blank; no document command is created.
    /// - Parameter target: Frozen source and original assignment values.
    public init(target: EdgeBoneAssignmentTarget) {
        self.target = target
        value = target.commonName ?? BoneNameIdentity("")
    }
    /// Preserve native UTF-8 changes; an unchanged submit callback does not mark a mixed blank as edited.
    public mutating func edit(_ value: BoneNameIdentity) {
        if self.value != value { edited = true }
        self.value = value
    }
    /// Restore captured display state without publishing a document command.
    public mutating func reset() {
        value = target.commonName ?? BoneNameIdentity("")
        edited = false
    }
}

/// A batch requires its original available source/selection context.
public enum EdgeBoneAssignmentError: LocalizedError, Equatable, Sendable {
    case staleTarget
    public var errorDescription: String? {
        "The selected edges are unavailable or have changed. Select editable edges before assigning a bone."
    }
}
