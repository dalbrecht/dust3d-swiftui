import Dust3DDocument

/// Pure stored-intent row; its byte identity avoids Swift canonical String identity collisions.
public struct AnimationListRow: Sendable, Identifiable {
    public let id: [UInt8]
    public let source: DocumentAnimation
    public let title: String
    public let typeLabel: String

    init(source: DocumentAnimation, index: Int) {
        id = Array(source.id.utf8)
        self.source = source
        title = source.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Animation \(index + 1)"
        typeLabel = source.type.flatMap { $0.isEmpty ? nil : $0 } ?? "Unspecified type"
    }
}

/// Read-only data-to-presentation transform; errors stay distinct from a successfully empty list.
public struct AnimationListPresentation: Sendable {
    public let rows: [AnimationListRow]
    public let selectedID: [UInt8]?
    /// Original optional-metadata cause, not a playback or generator error.
    public let issue: (any Error)?

    public var selectedRow: AnimationListRow? {
        guard let selectedID else { return nil }
        return rows.first { $0.id == selectedID }
    }

    /// Transform a validated document catalog without evaluating or rewriting its values.
    /// - Parameters:
    ///   - catalog: Result of the bounded document metadata reader; original failures are retained.
    ///   - selectedID: Exact source spelling; absent/stale selections normalize to nil.
    /// - Example: `AnimationListPresentation(catalog: .success(records), selectedID: id)`.
    public init(catalog: Result<[DocumentAnimation], any Error>, selectedID: String? = nil) {
        switch catalog {
        case .success(let records):
            let builtRows = records.enumerated().map { AnimationListRow(source: $0.element, index: $0.offset) }
            rows = builtRows
            let candidate = selectedID.map { Array($0.utf8) }
            self.selectedID = candidate.flatMap { candidate in
                builtRows.contains { $0.id == candidate } ? candidate : nil
            }
            issue = nil
        case .failure(let cause):
            rows = []
            self.selectedID = nil
            issue = cause
        }
    }
}

/// Document, history and optional list from one serial actor observation.
public struct EditorAnimationSnapshot: Sendable {
    public let editor: EditorSnapshot
    public let list: AnimationListPresentation
}
