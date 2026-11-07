import Dust3DEditorModel
import Foundation
import SwiftUI

@MainActor struct EditorGetStartedActions {
    private weak var store: EditorStore?
    private let admitsInput: @MainActor () -> Bool

    init?(
        store: EditorStore, fileIdentity: UUID, ownsWindow: @escaping @MainActor () -> Bool = { true }
    ) {
        guard ownsWindow(), let admitsSource = store.getStartedAdmission(fileIdentity: fileIdentity) else { return nil }
        self.store = store
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

    func drawFirstNode() {
        if canDrawFirstNode { store?.beginAddMode() }
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
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
