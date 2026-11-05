import Dust3DDocument
import Foundation

/// An explicit part or a graph object whose stored owner resolves the target; missing hover never chooses a fallback part.
public enum PartGraphTarget: Hashable, Sendable {
    case part(String)
    case node(String)
    case edge(String)
}

/// A queued targeted selection belongs to one document epoch; intervening selection alone does not change ownership.
public struct PartGraphSelectionContext: Sendable {
    private let documentIdentity: UUID
    private let documentRevision: Int

    /// Capture the source window before dispatching a targeted part/node/edge action.
    public init(snapshot: EditorSnapshot) {
        documentIdentity = snapshot.documentIdentity
        documentRevision = snapshot.documentRevision
    }

    /// Whether this target still refers to the same document snapshot, including after undo or replacement.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        documentIdentity == snapshot.documentIdentity && documentRevision == snapshot.documentRevision
    }
}

/// A reveal/scroll request independent of exclusive component selection and explicit graph selection.
public struct ComponentRevealHint: Equatable, Sendable {
    public let componentID: String
    /// Ancestors in root-to-parent order, to expand before revealing the owning row.
    public let ancestorIDs: [String]
    /// A distinct reveal epoch even when repeated part selection leaves graph selection unchanged.
    public let revision: Int

    static func make(partID: String, tree: ComponentTree, revision: Int) -> Self? {
        guard let owner = tree.rows.first(where: { $0.component.partID == partID }) else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: tree.rows.map { ($0.id, $0.component) })
        var ancestors: [String] = []
        var parentID = owner.component.parentID
        while let parent = parentID, let component = byID[parent] {
            ancestors.append(parent)
            parentID = component.parentID
        }
        return Self(componentID: owner.id, ancestorIDs: ancestors.reversed(), revision: revision)
    }
}

extension EditorSnapshot {
    /// Resolve an existing part using actual stored node/edge ownership, without inferring edge ownership from endpoints.
    /// - Parameter target: A part identity or explicitly targeted node/edge.
    /// - Returns: Nil for missing objects, absent owners or references to missing parts.
    /// - Example: `snapshot.partID(for: .edge(edgeID))`.
    public func partID(for target: PartGraphTarget) -> String? { try? resolvedPartGraphID(for: target) }

    /// Whether a targeted whole-part action has a real owner, including hidden/read-only inspection targets.
    public func canSelectWholePart(_ target: PartGraphTarget) -> Bool { partID(for: target) != nil }

    func resolvedPartGraphID(for target: PartGraphTarget) throws -> String {
        let partID: String
        switch target {
        case .part(let id): partID = id
        case .node(let id):
            guard let node = nodes.first(where: { $0.id == id }) else { throw DocumentError.missingNode(id) }
            guard let owner = node.partID, !owner.isEmpty else { throw DocumentError.invalidNode }
            partID = owner
        case .edge(let id):
            guard let edge = edges.first(where: { $0.id == id }), let owner = edge.partID, !owner.isEmpty else {
                throw DocumentError.invalidNode
            }
            partID = owner
        }
        guard parts.contains(where: { $0.id == partID }) else { throw DocumentError.missingPart(partID) }
        return partID
    }
}

/// A sidebar action captures exact component IDs and the document interaction epoch.
public struct ComponentGraphSelectionTarget: Sendable {
    let context: CanvasAdjustmentTarget
    let componentIDs: Set<Data>

    public init(snapshot: EditorSnapshot, componentIDs: Set<String>) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        self.componentIDs = Set(componentIDs.map { Data($0.utf8) })
    }
}

extension EditorSnapshot {
    /// Whether a captured component selection contains visible, editable graph objects.
    public func canSelectComponentGraph(_ target: ComponentGraphSelectionTarget) -> Bool {
        guard let graph = componentGraph(target) else { return false }
        return !graph.nodes.isEmpty || !graph.edges.isEmpty
    }

    func componentGraph(_ target: ComponentGraphSelectionTarget) -> (nodes: Set<String>, edges: Set<String>)? {
        let roots = target.componentIDs
        guard target.context.isCurrent(in: self), !roots.isEmpty,
            roots.isSubset(of: Set(componentTree.rows.map { Data($0.id.utf8) }))
        else { return nil }
        let editableParts = Set(parts.filter { $0.isVisible && !$0.isLocked }.map { Data($0.id.utf8) })
        var selectedDepth: Int?
        var partIDs: Set<Data> = []
        for row in componentTree.rows {
            if let depth = selectedDepth, row.depth <= depth { selectedDepth = nil }
            if selectedDepth == nil, roots.contains(Data(row.id.utf8)) { selectedDepth = row.depth }
            if selectedDepth != nil, let part = row.component.partID {
                let key = Data(part.utf8)
                if editableParts.contains(key) { partIDs.insert(key) }
            }
        }
        guard !partIDs.isEmpty else { return ([], []) }
        return (
            Set(
                nodes.compactMap { node in
                    guard let owner = node.partID, partIDs.contains(Data(owner.utf8)) else { return nil }
                    return node.id
                }),
            Set(
                edges.compactMap { edge in
                    guard let owner = edge.partID, partIDs.contains(Data(owner.utf8)) else { return nil }
                    return edge.id
                })
        )
    }
}
