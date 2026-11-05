import Foundation

/// One field-local replacement across explicit components of any role or link kind.
public enum ComponentMeshEdit: Sendable {
    /// Shared with the document hierarchy bound; captures and commands reject oversized input equally.
    public static let maximumBatchCount = ComponentHierarchy.maximumCount
    case combineMode(ComponentCombineMode)
    case smoothCutoffDegrees(Double)
}

/// Preflight every literal request once before changing the shared DOM.
enum ComponentMeshBatch {
    static func apply(_ model: XMLDocument, ids: [String], edit: ComponentMeshEdit) throws -> Bool {
        guard ids.count <= ComponentMeshEdit.maximumBatchCount else { throw DocumentError.limitExceeded }
        guard !ids.isEmpty else { return false }
        if case .smoothCutoffDegrees(let value) = edit, !ComponentSmoothing.isValid(value) {
            throw DocumentError.invalidComponentSmoothing
        }
        let components = try ComponentHierarchy.read(model)
        let available = Set(components.map { Data($0.id.utf8) })
        // Validate the array before deduplication: Swift String equality can collapse distinct UTF-8 requests.
        for id in ids where !available.contains(Data(id.utf8)) { throw DocumentError.missingComponent(id) }
        let selected = Set(ids.map { Data($0.utf8) })
        let elements = PartSplitting.componentElements(model)
        try Task.checkCancellation()
        var changed = false
        for element in elements {
            guard let id = element.attribute(forName: "id")?.stringValue,
                selected.contains(Data(id.utf8))
            else { continue }
            let didChange: Bool
            switch edit {
            case .combineMode(let mode): didChange = ComponentCombination.set(element, mode: mode)
            case .smoothCutoffDegrees(let value): didChange = ComponentSmoothing.set(element, degrees: value)
            }
            changed = didChange || changed
        }
        try Task.checkCancellation()
        return changed
    }
}
