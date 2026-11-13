import Dust3DDocument
import Dust3DEditorModel
import Foundation
import Observation
import SwiftUI

struct RigAssignmentCommandFocus {
    var hasKeyWindow = true
    var hasSheet = false
    var textEditing = false
    var animationFocused = false

    var allowsAssignment: Bool { hasKeyWindow && !hasSheet && !textEditing && !animationFocused }
}

/// The tree's exact selection and lifetime retire commands even after a name or visibility ABA.
@MainActor @Observable
final class RigAssignmentBrowserSelection {
    private var selectedBone: BoneNameIdentity?
    var selectedName: String? { selectedBone?.rawValue }
    private var isVisible = false
    private var revision = UUID()

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        revision = UUID()
    }

    func select(_ name: String?) {
        let identity = name.map(BoneNameIdentity.init)
        guard selectedBone != identity else { return }
        selectedBone = identity
        revision = UUID()
    }

    func command(
        store: EditorStore, context: RigTemplateBrowserContext, isPresented: @escaping @MainActor () -> Bool = { true }
    ) -> RigAssignmentCommand? {
        guard isVisible, isPresented(), let selectedName, context.contains(selectedName), let snapshot = store.snapshot,
            context.isCurrent(in: snapshot), store.canAssignTemplateBoneName(selectedName, target: context.assignment)
        else { return nil }
        let expectedRevision = revision
        return RigAssignmentCommand(store: store, name: selectedName, target: context.assignment) { [weak self] in
            self?.isVisible == true && self?.revision == expectedRevision && isPresented()
        }
    }

    func clearCommand(
        for name: String, includeDescendants: Bool, store: EditorStore, context: RigTemplateBrowserContext,
        isPresented: @escaping @MainActor () -> Bool = { true }
    ) -> (@MainActor () -> Void)? {
        guard isVisible, isPresented(), store.canSave, let snapshot = store.snapshot, context.isCurrent(in: snapshot),
            context.hasAssignments(name: name, includeDescendants: includeDescendants)
        else { return nil }
        let expectedRevision = revision
        return { [weak self, weak store] in
            guard let self, self.isVisible, self.revision == expectedRevision, isPresented(),
                let store, let snapshot = store.snapshot, context.isCurrent(in: snapshot),
                let target = context.clearTarget(name: name, includeDescendants: includeDescendants)
            else { return }
            store.clearBoneAssignmentsAction(target)()
        }
    }

}

@MainActor struct RigAssignmentCommand {
    private weak var store: EditorStore?
    private let name: String
    private let target: EdgeBoneAssignmentTarget
    private let isCurrentBrowser: @MainActor () -> Bool
    private let assign: @MainActor () -> Void

    init(
        store: EditorStore, name: String, target: EdgeBoneAssignmentTarget,
        isCurrentBrowser: @escaping @MainActor () -> Bool
    ) {
        self.store = store
        self.name = name
        self.target = target
        self.isCurrentBrowser = isCurrentBrowser
        assign = store.assignBoneNameAction(name, target: target)
    }

    func canInvoke(in currentStore: EditorStore?, focus: RigAssignmentCommandFocus = .init()) -> Bool {
        guard focus.allowsAssignment, let store, store === currentStore, isCurrentBrowser() else { return false }
        return store.canAssignTemplateBoneName(name, target: target)
    }

    @discardableResult
    func invoke(in currentStore: EditorStore?, focus: RigAssignmentCommandFocus = .init()) -> Bool {
        guard canInvoke(in: currentStore, focus: focus) else { return false }
        assign()
        return true
    }
}

private struct RigAssignmentCommandKey: FocusedValueKey { typealias Value = RigAssignmentCommand }

extension FocusedValues {
    var rigAssignmentCommand: RigAssignmentCommand? {
        get { self[RigAssignmentCommandKey.self] }
        set { self[RigAssignmentCommandKey.self] = newValue }
    }
}
