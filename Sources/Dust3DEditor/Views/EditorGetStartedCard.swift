import Dust3DEditorModel
import Foundation
import SwiftUI

@MainActor struct EditorGetStartedActions {
    private weak var store: EditorStore?
    private let admitsInput: @MainActor () -> Bool
    private let setAddMode: @MainActor (Bool) -> Void

    init?(
        store: EditorStore, fileIdentity: UUID, ownsWindow: @escaping @MainActor () -> Bool = { true }
    ) {
        guard ownsWindow(), let admitsSource = store.getStartedAdmission(fileIdentity: fileIdentity) else { return nil }
        self.store = store
        setAddMode = store.addPlacementToggleAction()
        admitsInput = { ownsWindow() && admitsSource() }
    }

    var canDrawFirstNode: Bool { admitsInput() && store?.canBeginAddMode == true }

    func open(_ action: @MainActor () -> Void) {
        if admitsInput() { action() }
    }

    func compose(_ action: @MainActor (ReferenceCompositionTarget) -> Void) {
        guard admitsInput(), let target = store?.referenceCompositionTarget else { return }
        action(target)
    }

    func referenceDrop(_ urls: [URL]) -> ReferenceCompositionPresentation? {
        guard admitsInput(), let target = store?.referenceCompositionTarget,
            let drop = ReferenceCompositionDrop(urls: urls)
        else { return nil }
        return ReferenceCompositionPresentation(target: target, droppedSources: drop)
    }

    func drawFirstNode() {
        if canDrawFirstNode { setAddMode(true) }
    }
}

struct EditorGetStartedCard: View {
    let actions: EditorGetStartedActions
    let openDocument: @MainActor () -> Void
    let composeReference: @MainActor (ReferenceCompositionTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Get Started").font(.headline).accessibilityAddTraits(.isHeader)
            Button("Draw First Node", action: actions.drawFirstNode)
                .disabled(!actions.canDrawFirstNode)
            Button("Compose Reference Image…") { actions.compose(composeReference) }
            Button("Open Document…") { actions.open(openDocument) }
            Text("Drop one or two reference images on the canvas.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
