import Dust3DDocument
import Dust3DEditorModel
import Foundation
import Observation

enum EditorAnimationAuthoringError: LocalizedError, Equatable {
    case chooseType
    var errorDescription: String? { "Choose a declared animation type." }
}

/// One captured inspector draft; only an explicit Apply invokes a document transaction.
@MainActor @Observable
final class EditorAnimationAuthoringWorkflow {
    enum Mode {
        case idle
        case create(AnimationCreationTarget)
        case type(AnimationEditTarget)
        case parameters(AnimationEditTarget)
    }
    private let store: EditorStore
    private var stopped = false
    private var lastIssue: (any Error)?
    private(set) var mode = Mode.idle
    private(set) var sourceTitle = ""
    private(set) var sourceType: String?
    private(set) var parameterDraft: AnimationParameterDraft?
    private(set) var isSubmitting = false
    var name = AnimationNameText("")
    var selectedType: [UInt8] = []

    init(store: EditorStore) { self.store = store }
    var catalog: AnimationAuthoringCatalog? { store.authoringCatalog.catalog }
    var isActive: Bool { if case .idle = mode { false } else { true } }
    private var canBegin: Bool { !stopped && !isActive && !isSubmitting && store.canManageAnimations && catalog != nil }
    var canBeginCreation: Bool { canBegin && catalog?.clips.isEmpty == false }
    var canBeginType: Bool { canBeginCreation && store.animationSnapshot?.list.selectedRow != nil }
    var canBeginParameters: Bool {
        guard canBegin, let type = store.animationSnapshot?.list.selectedRow?.source.type else { return false }
        return catalog?.clip(type: type) != nil
    }
    var selectedClip: AnimationClipDefinition? {
        catalog?.clips.first { $0.type.utf8.elementsEqual(selectedType) }
    }
    var isCurrent: Bool {
        guard let snapshot = store.snapshot else { return false }
        switch mode {
        case .idle: return false
        case .create(let target): return target.isCurrent(in: snapshot)
        case .type(let target), .parameters(let target): return target.isCurrent(in: snapshot)
        }
    }
    var validationIssue: (any Error)? {
        if isSubmitting { return nil }
        if isActive, !isCurrent { return EditorError.staleAnimationTarget }
        if let lastIssue { return lastIssue }
        do {
            switch mode {
            case .idle: break
            case .create:
                guard let clip = selectedClip, let catalog else { return EditorAnimationAuthoringError.chooseType }
                _ = try AnimationParameterDraft.initialParameters(for: clip, in: catalog)
            case .type:
                if selectedClip == nil { return EditorAnimationAuthoringError.chooseType }
            case .parameters:
                _ = try parameterDraft?.validatedEdits()
            }
        } catch { return error }
        return nil
    }
    var validationMessage: String? {
        guard let issue = validationIssue else { return nil }
        if issue as? EditorError == .staleAnimationTarget {
            return "The document changed. Cancel and start this draft again."
        }
        return EditorStore.message(issue)
    }

    var canApply: Bool {
        guard !stopped, isActive, !isSubmitting, store.canManageAnimations, validationIssue == nil else { return false }
        switch mode {
        case .idle: return false
        case .create: return true
        case .type: return !selectedType.elementsEqual((sourceType ?? "").utf8)
        case .parameters: return (try? parameterDraft?.validatedEdits().isEmpty) == false
        }
    }

    func beginCreation() {
        guard canBeginCreation, let value = store.animationSnapshot, let clip = catalog?.clips.first else { return }
        do {
            let target = try AnimationCreationTarget(snapshot: value)
            reset()
            name = AnimationNameText(clip.type)
            selectedType = Array(clip.type.utf8)
            mode = .create(target)
        } catch { lastIssue = error }
    }
    func beginType() {
        guard canBeginType, let value = store.animationSnapshot, let row = value.list.selectedRow else { return }
        do {
            let target = try AnimationEditTarget(snapshot: value, animationID: row.source.id)
            reset()
            sourceTitle = row.title
            sourceType = row.source.type
            selectedType = Array((row.source.type ?? "").utf8)
            mode = .type(target)
        } catch { lastIssue = error }
    }
    func beginParameters() {
        guard canBeginParameters, let value = store.animationSnapshot, let row = value.list.selectedRow, let catalog
        else {
            return
        }
        do {
            let target = try AnimationEditTarget(snapshot: value, animationID: row.source.id)
            let draft = try AnimationParameterDraft(record: row.source, catalog: catalog)
            reset()
            sourceTitle = row.title
            sourceType = row.source.type
            parameterDraft = draft
            mode = .parameters(target)
        } catch { lastIssue = error }
    }
    func setText(name: String, value: String?) {
        guard !isSubmitting, var draft = parameterDraft else { return }
        draft.setText(name: name, value: value)
        parameterDraft = draft
        lastIssue = nil
    }
    func useDefault(name: String) { setText(name: name, value: nil) }
    func setSlider(name: String, index: Double) {
        guard !isSubmitting, var draft = parameterDraft else { return }
        do {
            guard let index = Int32(exactly: index) else { throw AnimationCatalogError.invalidValue }
            try draft.setSlider(name: name, index: Int(index))
            parameterDraft = draft
            lastIssue = nil
        } catch { lastIssue = error }
    }

    func submit() {
        guard canApply else { return }
        let completion: @MainActor (Bool) -> Void = { [weak self] accepted in
            guard let self, !stopped else { return }
            isSubmitting = false
            if accepted { reset() }
        }
        do {
            switch mode {
            case .idle: return
            case .create(let target):
                guard let clip = selectedClip, let catalog else { throw EditorAnimationAuthoringError.chooseType }
                let parameters = try AnimationParameterDraft.initialParameters(for: clip, in: catalog)
                isSubmitting = true
                store.createAnimation(
                    name: name.value, type: clip.type, parameters: parameters, target: target, completion: completion)
            case .type(let target):
                guard let clip = selectedClip else { throw EditorAnimationAuthoringError.chooseType }
                isSubmitting = true
                store.editAnimation(.setType(clip.type), target: target, completion: completion)
            case .parameters(let target):
                guard let draft = parameterDraft else { return }
                let edits = try draft.validatedEdits()
                isSubmitting = true
                store.editAnimation(edits, target: target, completion: completion)
            }
        } catch {
            isSubmitting = false
            lastIssue = error
        }
    }
    func cancel() { if !isSubmitting { reset() } }
    func stop() {
        stopped = true
        isSubmitting = false
        reset()
    }
    private func reset() {
        mode = .idle
        sourceTitle = ""
        sourceType = nil
        parameterDraft = nil
        selectedType = []
        name = AnimationNameText("")
        lastIssue = nil
    }
}
