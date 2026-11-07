import SwiftUI

/// Scene-scoped rest controls recheck their document and presentation before writing.
@MainActor
struct EditorRestPreviewActions {
    private let isCurrent: @MainActor () -> Bool
    private let readMode: @MainActor () -> GeneratedRigPreviewSession.Presentation
    private let writeMode: @MainActor (GeneratedRigPreviewSession.Presentation) -> Void
    private let readModel: @MainActor () -> Bool
    private let writeModel: @MainActor (Bool) -> Void
    private let readBones: @MainActor () -> Bool
    private let writeBones: @MainActor (Bool) -> Void
    private let readWeights: @MainActor () -> Bool
    private let writeWeights: @MainActor (Bool) -> Void
    private let readCanReveal: @MainActor () -> Bool
    private let revealJoint: @MainActor () -> Void

    init(
        isCurrent: @escaping @MainActor () -> Bool = { true },
        mode: @escaping @MainActor () -> GeneratedRigPreviewSession.Presentation,
        setMode: @escaping @MainActor (GeneratedRigPreviewSession.Presentation) -> Void,
        showsModel: @escaping @MainActor () -> Bool, setShowsModel: @escaping @MainActor (Bool) -> Void,
        showsBones: @escaping @MainActor () -> Bool, setShowsBones: @escaping @MainActor (Bool) -> Void,
        showsWeights: @escaping @MainActor () -> Bool, setShowsWeights: @escaping @MainActor (Bool) -> Void,
        canRevealSelectedJoint: @escaping @MainActor () -> Bool = { false },
        revealSelectedJoint: @escaping @MainActor () -> Void = {}
    ) {
        self.isCurrent = isCurrent
        readMode = mode
        writeMode = setMode
        readModel = showsModel
        writeModel = setShowsModel
        readBones = showsBones
        writeBones = setShowsBones
        readWeights = showsWeights
        writeWeights = setShowsWeights
        readCanReveal = canRevealSelectedJoint
        revealJoint = revealSelectedJoint
    }

    var canChangeMode: Bool { isCurrent() }
    var mode: GeneratedRigPreviewSession.Presentation { canChangeMode ? readMode() : .model }
    var canChangeVisibility: Bool { canChangeMode && readMode() == .generatedRest }
    var showsModel: Bool { canChangeVisibility && readModel() }
    var showsBones: Bool { canChangeVisibility && readBones() }
    var showsWeights: Bool { canChangeVisibility && readWeights() }

    var canRevealSelectedJoint: Bool { canChangeVisibility && readCanReveal() }
    func revealSelectedJoint() {
        guard canRevealSelectedJoint else { return }
        revealJoint()
    }

    func setMode(_ value: GeneratedRigPreviewSession.Presentation) {
        guard canChangeMode else { return }
        writeMode(value)
    }
    func setShowsModel(_ value: Bool) {
        guard canChangeVisibility else { return }
        writeModel(value)
    }
    func setShowsBones(_ value: Bool) {
        guard canChangeVisibility else { return }
        writeBones(value)
    }
    func setShowsWeights(_ value: Bool) {
        guard canChangeVisibility else { return }
        writeWeights(value)
    }
}

private struct EditorRestPreviewActionsKey: FocusedValueKey { typealias Value = EditorRestPreviewActions }

extension FocusedValues {
    var editorRestPreviewActions: EditorRestPreviewActions? {
        get { self[EditorRestPreviewActionsKey.self] }
        set { self[EditorRestPreviewActionsKey.self] = newValue }
    }
}
