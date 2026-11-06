import Dust3DDocument
import Foundation

/// A mixed or unsupported display never supplies an implicit authored value.
public enum ComponentWrappingSelectionValue<Value: Equatable & Sendable>: Equatable, Sendable {
    case uniform(Value)
    case mixed
    case unsupported

    static func read(_ values: [Value?]) -> Self {
        guard let first = values.first else { return .unsupported }
        guard values.allSatisfy({ $0 == first }) else { return .mixed }
        return first.map(Self.uniform) ?? .unsupported
    }
}

/// One rendered sidebar selection, including document, selection and constraint ABA protection.
public struct ComponentWrappingSelectionTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    let ids: [String]

    /// Capture directly selected supported group rows; inactive and unknown modes stay eligible.
    /// - Parameter snapshot: The immutable originating window snapshot.
    public init(snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        let rows = snapshot.selectedComponentRows
        ids =
            !rows.isEmpty && rows.count == snapshot.selectedComponentIDs.count
                && rows.allSatisfy { $0.component.isGroup } ? rows.map(\.id) : []
    }
    /// Reject source, selection or constraint changes, including away-and-back transitions.
    /// - Parameter snapshot: The current actor or UI snapshot.
    /// - Returns: True only for the original admitted selection.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        !ids.isEmpty && context.isCurrent(in: snapshot)
            && Set(ids.map { Data($0.utf8) }) == Set(snapshot.selectedComponentIDs.map { Data($0.utf8) })
    }
}

/// Common values are informational; every explicit edit still applies to all selected groups.
public struct ComponentWrappingSelectionPresentation: Sendable {
    public let groups: [DocumentComponent]
    public let mode: ComponentWrappingSelectionValue<ComponentWrapMode>
    public var isAvailable: Bool { !groups.isEmpty }
    public var showsClothFields: Bool { groups.contains { $0.wrapping.mode == .cloth } }
    public init(snapshot: EditorSnapshot) {
        let target = ComponentWrappingSelectionTarget(snapshot: snapshot)
        groups = target.isCurrent(in: snapshot) ? snapshot.selectedComponentRows.map(\.component) : []
        mode = .read(groups.map { $0.wrapping.mode })
    }
    public func scalar(_ property: ComponentWrappingScalarProperty) -> ComponentWrappingSelectionValue<Double> {
        .read(groups.map { $0.wrapping.scalarValue(property) })
    }
    /// Exact source values across the selection; absent and stored empty values remain distinct.
    public var binding: ComponentWrappingSelectionValue<ComponentWrapBindingValue> {
        .read(groups.map { $0.wrapping.binding })
    }
    public var keepChildren: ComponentWrappingSelectionValue<Bool> { .read(groups.map { $0.wrapping.keepsChildren }) }
    public var faces: ComponentWrappingSelectionValue<Int> { .read(groups.map { $0.wrapping.targetFaces }) }
    public var ink: ComponentWrappingSelectionValue<ComponentColorValue> {
        .read(groups.map { $0.wrapping.surfaceDetails.ink })
    }
    public var pattern: ComponentWrappingSelectionValue<ComponentSurfacePattern> {
        .read(groups.map { $0.wrapping.surfaceDetails.pattern })
    }
    public func surfaceScalar(_ property: ComponentSurfaceScalar) -> ComponentWrappingSelectionValue<Double> {
        .read(groups.map { $0.wrapping.surfaceDetails.scalarValue(property) })
    }
}

public enum ComponentWrappingSelectionError: Error, Equatable, Sendable { case staleTarget }

extension EditorState {
    /// Validate the original selection and publish one atomic undo step after cooperative cancellation.
    /// - Parameters: edit replaces one field; target captures the originating group selection.
    /// - Throws: Stale target, document validation errors or cancellation before publication.
    /// - Example: `try state.editSelectedComponentWrapping(.mode(.cloth), target: target)`.
    public mutating func editSelectedComponentWrapping(
        _ edit: ComponentWrappingEdit, target: ComponentWrappingSelectionTarget
    ) throws {
        guard target.isCurrent(in: snapshot) else { throw ComponentWrappingSelectionError.staleTarget }
        var next = self
        try next.apply([.editComponentWrapping(ids: target.ids, edit: edit)])
        try Task.checkCancellation()
        self = next
    }
}
