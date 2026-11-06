import Dust3DDocument
import Dust3DEditorModel
import Foundation
import Observation

/// A cancellable picker/text session. Obsolete native callbacks cannot repopulate a reset draft.
@MainActor @Observable final class SurfaceInkDraft {
    private(set) var color: ComponentColorDraft
    private(set) var generation = UUID()
    var canApply: Bool { color.conversionIssue == nil && color.parsedColor?.alpha == 255 }

    init(source: ComponentColorValue) { color = ComponentColorDraft(source: source) }
    func cancel(source: ComponentColorValue) {
        generation = UUID()
        color = ComponentColorDraft(source: source)
    }
    func choosingAction(canEdit: @escaping @MainActor () -> Bool) -> @MainActor (DocumentColor?) -> Void {
        guard canEdit() else { return { _ in } }
        let captured = generation
        return { [weak self] value in
            guard let self, captured == self.generation, canEdit() else { return }
            self.color = self.color.choosing(value)
        }
    }
    func editingAction(canEdit: @escaping @MainActor () -> Bool) -> @MainActor (String) -> Void {
        guard canEdit() else { return { _ in } }
        let captured = generation
        return { [weak self] value in
            guard let self, captured == self.generation, canEdit() else { return }
            self.color = self.color.editing(value)
        }
    }
}
