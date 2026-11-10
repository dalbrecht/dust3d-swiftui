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
    enum EditKind { case type, parameters }

    private let store: EditorStore
    private var stopped = false
    private var parameterControlsID = UUID()
    private var lastIssue: (any Error)?
    private(set) var mode = Mode.idle
    private(set) var sourceTitle = ""
    private(set) var sourceType: String?
    private(set) var parameterDraft: AnimationParameterDraft?
    private(set) var unknownParameterDraft: UnknownAnimationParameterDraft?
    private(set) var isSubmitting = false
    private var creationNameKeys: Set<String> = []
    private var suggestedName = AnimationNameText("")
    private var manualName: AnimationNameText?
    var name: AnimationNameText {
        get { manualName ?? suggestedName }
        set { manualName = newValue }
    }
    var selectedType: [UInt8] = [] {
        didSet {
            guard case .create = mode, manualName == nil, isCurrent, let clip = selectedClip else { return }
            suggestedName = AnimationNameText(suggestedCreationName(for: clip))
        }
    }

    init(store: EditorStore) { self.store = store }
    var catalog: AnimationAuthoringCatalog? { store.authoringCatalog.catalog }
    var isActive: Bool { if case .idle = mode { false } else { true } }
    private var canBegin: Bool { !stopped && !isActive && !isSubmitting && store.canManageAnimations && catalog != nil }
    var creationClips: [AnimationClipDefinition] {
        guard let rig = store.animationSnapshot?.editor.rigSettings.sourceRigType, !rig.isEmpty, let catalog else {
            return []
        }
        return catalog.clips.filter { !$0.isLegacyAlias && $0.rig.caseInsensitiveCompare(rig) == .orderedSame }
    }
    var typeChoices: [AnimationClipDefinition] {
        if case .create = mode { return creationClips }
        return catalog?.clips ?? []
    }
    var canBeginCreation: Bool { canBegin && !creationClips.isEmpty }
    var canBeginType: Bool {
        canBegin && catalog?.clips.isEmpty == false && store.animationSnapshot?.list.selectedRow != nil
    }
    var canBeginParameters: Bool {
        guard canBegin, let record = store.animationSnapshot?.list.selectedRow?.source, let type = record.type
        else { return false }
        return catalog?.clip(type: type) != nil || UnknownAnimationParameterDraft.admits(record)
    }
    var selectedClip: AnimationClipDefinition? {
        typeChoices.first { $0.type.utf8.elementsEqual(selectedType) }
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
                _ = try validatedParameterEdits()
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
        case .parameters: return (try? validatedParameterEdits().isEmpty) == false
        }
    }

    func creationAction() -> @MainActor () -> Void {
        guard canBeginCreation, let value = store.animationSnapshot,
            let target = try? AnimationCreationTarget(snapshot: value)
        else { return {} }
        return { [weak self] in
            guard let self, canBeginCreation, let current = store.animationSnapshot,
                target.isCurrent(in: current.editor), let clip = creationClips.first
            else { return }
            reset()
            creationNameKeys = Set(current.list.rows.compactMap { $0.source.name }.map(Self.creationNameKey))
            mode = .create(target)
            selectedType = Array(clip.type.utf8)
        }
    }
    private static func creationNameKey(_ name: String) -> String {
        name.folding(options: .caseInsensitive, locale: nil)
    }

    private func suggestedCreationName(for clip: AnimationClipDefinition) -> String {
        let prefix = clip.type.range(of: clip.rig, options: [.anchored, .caseInsensitive])
        let stripped = prefix.map { clip.type[$0.upperBound...] } ?? clip.type[...]
        let stem = stripped.isEmpty ? clip.type[...] : stripped
        let base = stem.prefix(1).lowercased() + stem.dropFirst()
        var candidate = base
        var suffix = 2
        while creationNameKeys.contains(Self.creationNameKey(candidate)) {
            candidate = base + String(suffix)
            suffix += 1
        }
        return candidate
    }

    func editAction(_ kind: EditKind) -> @MainActor () -> Void {
        guard kind == .type ? canBeginType : canBeginParameters, let snapshot = store.animationSnapshot else {
            return {}
        }
        return store.animationSelectedRowAction(snapshot: snapshot) { [weak self] row, target in
            guard let self, kind == .type ? canBeginType : canBeginParameters, let catalog else { return }
            switch kind {
            case .type:
                reset()
                sourceTitle = row.title
                sourceType = row.source.type
                selectedType = Array((row.source.type ?? "").utf8)
                mode = .type(target)
            case .parameters:
                do {
                    let hasDeclaredType = row.source.type.flatMap { catalog.clip(type: $0) } != nil
                    let draft =
                        hasDeclaredType ? try AnimationParameterDraft(record: row.source, catalog: catalog) : nil
                    reset()
                    sourceTitle = row.title
                    sourceType = row.source.type
                    parameterDraft = draft
                    if !hasDeclaredType {
                        unknownParameterDraft = UnknownAnimationParameterDraft(record: row.source, catalog: catalog)
                    }
                    mode = .parameters(target)
                } catch { lastIssue = error }
            }
        }
    }
    func parameterValue(for name: String) -> String? {
        parameterDraft?.value(for: name) ?? unknownParameterDraft?.value(for: name)
    }
    func parameterAction<Value>(_ action: @escaping @MainActor (EditorAnimationAuthoringWorkflow, Value) -> Void)
        -> @MainActor (Value) -> Void
    {
        let controlsID = parameterControlsID
        return { [weak self] value in
            guard let self, !stopped, !isSubmitting, isCurrent, parameterControlsID == controlsID else { return }
            action(self, value)
        }
    }

    func setText(name: String, value: String?) {
        guard !isSubmitting else { return }
        if var draft = parameterDraft {
            draft.setText(name: name, value: value)
            parameterDraft = draft
        } else {
            unknownParameterDraft?.setText(name: name, value: value)
        }
        lastIssue = nil
    }

    private func validatedParameterEdits() throws -> [AnimationEdit] {
        if let parameterDraft { return try parameterDraft.validatedEdits() }
        return try unknownParameterDraft?.validatedEdits() ?? []
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
                let edits = try validatedParameterEdits()
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
        parameterControlsID = UUID()
        mode = .idle
        sourceTitle = ""
        sourceType = nil
        parameterDraft = nil
        unknownParameterDraft = nil
        selectedType = []
        creationNameKeys = []
        suggestedName = AnimationNameText("")
        manualName = nil
        lastIssue = nil
    }
}
