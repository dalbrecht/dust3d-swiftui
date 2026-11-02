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

/// Exact directly selected component rows, independent of role, link kind and graph locks.
public struct ComponentMeshSelectionTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    let ids: [String]
    public var count: Int { ids.count }

    /// Capture every raw selected identity before any deduplication or row projection.
    /// - Parameter snapshot: The immutable originating window/document selection.
    public init(snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
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
    /// Reject unavailable intent and document, selection or constraint changes, including ABA.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        !ids.isEmpty && context.isCurrent(in: snapshot)
            && Set(ids.map { Data($0.utf8) }) == Set(snapshot.selectedComponentIDs.map { Data($0.utf8) })
    }
}

/// Effective common values preserve source spellings and do not expand selected groups.
public struct ComponentMeshSelectionPresentation: Sendable {
    public let components: [DocumentComponent]
    public let combineMode: ComponentMeshSelectionValue<ComponentCombineMode>
    public let smoothCutoffDegrees: ComponentMeshSelectionValue<Double>
    public var isAvailable: Bool { components.count > 1 }

    /// Derive common display state without writing XML or guessing an unsupported value.
    public init(snapshot: EditorSnapshot) {
        let target = ComponentMeshSelectionTarget(snapshot: snapshot)
        let keys = Set(target.ids.map { Data($0.utf8) })
        components =
            target.isCurrent(in: snapshot)
            ? snapshot.componentTree.rows.filter { keys.contains(Data($0.id.utf8)) }.map(\.component) : []
        combineMode = .read(components.map(\.combineMode))
        smoothCutoffDegrees = .read(components.map(\.smoothCutoffDegrees))
    }
}

/// A retained inspector cannot replace settings on a later selection or archive.
public enum ComponentMeshSelectionError: Error, Equatable, Sendable { case staleTarget }

extension EditorState {
    /// Replace one field on all explicitly selected rows in one cancellable transaction.
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
