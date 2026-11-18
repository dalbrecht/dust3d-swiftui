import Dust3DDocument
import Foundation

/// Common settings are informational; mixed and unsupported states never supply an implicit edit.
public enum ComponentMeshSelectionValue<Value: Equatable & Sendable>: Equatable, Sendable {
    case uniform(Value)
    case mixed
    case unsupported

    static func read(_ values: [Value?]) -> Self {
        guard let first = values.first else { return .unsupported }
        guard values.allSatisfy({ $0 == first }) else { return .mixed }
        return first.map(Self.uniform) ?? .unsupported
    }
}

/// Exact component rows captured from the sidebar or explicit graph picks.
public struct ComponentMeshSelectionTarget: Hashable, Sendable {
    private let context: CanvasAdjustmentTarget
    package let ids: [String]
    package let isGraphSelection: Bool
    public var count: Int { ids.count }

    /// Capture every raw selected identity before any deduplication or row projection.
    /// - Parameter snapshot: The immutable originating window/document selection.
    public init(snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        isGraphSelection = false
        let requested = Array(snapshot.selectedComponentIDs)
        let available = Set(snapshot.componentTree.rows.map { Data($0.id.utf8) })
        guard !requested.isEmpty, requested.count <= ComponentMeshEdit.maximumBatchCount,
            requested.allSatisfy({ available.contains(Data($0.utf8)) })
        else {
            ids = []
            return
        }
        let keys = Set(requested.map { Data($0.utf8) })
        ids = snapshot.componentTree.rows.filter { keys.contains(Data($0.id.utf8)) }.map(\.id)
    }
    /// Capture one unique linked component per authored part owner. Ambiguous or missing owners make the batch unavailable.
    package init(graphSelection snapshot: EditorSnapshot, hovered: PartGraphTarget? = nil) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        isGraphSelection = true
        let selected = snapshot.explicitGraphPartKeys()
        guard selected != nil || (snapshot.selectedIDs.isEmpty && snapshot.selectedEdgeIDs.isEmpty) else {
            ids = []
            return
        }
        var partKeys = selected ?? []
        if let hovered {
            guard let owner = snapshot.partID(for: hovered) else {
                ids = []
                return
            }
            partKeys.insert(Data(owner.utf8))
        }
        let available = Set(snapshot.parts.map { Data($0.id.utf8) })
        guard partKeys.count <= ComponentMeshEdit.maximumBatchCount, partKeys.isSubset(of: available) else {
            ids = []
            return
        }
        let linkedRows = snapshot.componentTree.rows.filter { row in
            row.component.partID.map { partKeys.contains(Data($0.utf8)) } == true
        }
        let linkedKeys = Set(linkedRows.compactMap { $0.component.partID.map { Data($0.utf8) } })
        ids = linkedKeys == partKeys && linkedRows.count == partKeys.count ? linkedRows.map(\.id) : []
    }

    func soleGraphLinkedOwner(in snapshot: EditorSnapshot) -> (part: DocumentPart, component: DocumentComponent)? {
        guard isGraphSelection, ids.count == 1, let componentID = ids.first,
            let component = snapshot.componentTree.rows.first(where: { $0.id.utf8.elementsEqual(componentID.utf8) })?
                .component,
            let partID = component.partID,
            let part = snapshot.parts.first(where: { $0.id.utf8.elementsEqual(partID.utf8) })
        else { return nil }
        return (part, component)
    }

    /// Graph image authoring requires every explicit owner to be an exact linked Model part.
    package func graphColorImageComponents(in snapshot: EditorSnapshot) -> [DocumentComponent] {
        guard isGraphSelection, isCurrent(in: snapshot) else { return [] }
        let wanted = Set(ids.map { Data($0.utf8) })
        let modelParts = Set(snapshot.parts.filter { $0.target == .model }.map { Data($0.id.utf8) })
        let components = snapshot.componentTree.rows.map(\.component).filter { wanted.contains(Data($0.id.utf8)) }
        guard components.count == ids.count,
            components.allSatisfy({ $0.partID.map { modelParts.contains(Data($0.utf8)) } == true })
        else { return [] }
        return components
    }

    /// Reject unavailable intent and document, selection or constraint changes, including ABA.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        guard !ids.isEmpty, context.isCurrent(in: snapshot) else { return false }
        return isGraphSelection
            || Set(ids.map { Data($0.utf8) }) == Set(snapshot.selectedComponentIDs.map { Data($0.utf8) })
    }
}

/// Effective common values preserve source spellings and do not expand selected groups.
public struct ComponentMeshSelectionPresentation: Sendable {
    public let components: [DocumentComponent]
    public let combineMode: ComponentMeshSelectionValue<ComponentCombineMode>
    public let showsSmoothing: Bool
    public let smoothCutoffDegrees: ComponentMeshSelectionValue<Double>
    public let isAvailable: Bool

    /// Derive common display state without writing XML or guessing an unsupported value.
    public init(snapshot: EditorSnapshot) {
        self.init(snapshot: snapshot, target: ComponentMeshSelectionTarget(snapshot: snapshot))
    }

    package init(snapshot: EditorSnapshot, target: ComponentMeshSelectionTarget) {
        let keys = Set(target.ids.map { Data($0.utf8) })
        components =
            target.isCurrent(in: snapshot)
            ? snapshot.componentTree.rows.filter { keys.contains(Data($0.id.utf8)) }.map(\.component) : []
        isAvailable = components.count > (target.isGraphSelection ? 0 : 1)
        combineMode = .read(components.map(\.combineMode))
        showsSmoothing = snapshot.showsComponentSmoothing(for: components)
        smoothCutoffDegrees = .read(components.map(\.smoothCutoffDegrees))
    }
}

extension EditorSnapshot {
    /// Match the Qt inspector when the rows directly link to exactly one CutFace part.
    public func showsComponentSmoothing(for components: [DocumentComponent]) -> Bool {
        let linkedParts = Set(components.compactMap(\.partID).map { Data($0.utf8) })
        guard linkedParts.count == 1, let linkedPart = linkedParts.first else { return true }
        return !parts.contains { Data($0.id.utf8) == linkedPart && $0.target == .cutFace }
    }
}

/// A retained inspector cannot replace settings on a later selection or archive.
public enum ComponentMeshSelectionError: Error, Equatable, Sendable { case staleTarget }

extension EditorState {
    /// Replace one field on the captured component rows in one cancellable transaction.
    /// - Throws: Stale target, invalid field/identity, or cancellation without partial publication.
    public mutating func editSelectedComponentMeshSettings(
        _ edit: ComponentMeshEdit, target: ComponentMeshSelectionTarget
    ) throws {
        try Task.checkCancellation()
        guard target.isCurrent(in: snapshot) else { throw ComponentMeshSelectionError.staleTarget }
        var next = self
        try next.apply([.editComponentMeshSettings(ids: target.ids, edit: edit)])
        try Task.checkCancellation()
        self = next
    }
}
