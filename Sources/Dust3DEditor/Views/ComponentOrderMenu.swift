import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct ComponentOrderMenu: View {
    let store: EditorStore

    var body: some View {
        Menu("Reorder Component") {
            ForEach(ComponentOrderMove.allCases, id: \.self) { direction in
                Button(title(direction)) { store.reorderComponent(direction) }
                    .disabled(!store.canReorderComponent(direction))
            }
        }
        .accessibilityLabel("Reorder component among siblings")
        .disabled(store.isWorking || store.snapshot?.selectedComponentID == nil)
        .help("Changes order within this parent in one undo step. Component order can affect mesh combination.")
    }

    private func title(_ direction: ComponentOrderMove) -> String {
        switch direction {
        case .up: "Move Up"
        case .down: "Move Down"
        case .first: "Move to Top"
        case .last: "Move to Bottom"
        }
    }
}

/// Native sibling selection and explicit placement for a single component or a selected block.
struct ComponentBatchOrderMenu: View {
    let store: EditorStore
    let snapshot: EditorSnapshot

    var body: some View {
        let siblings = Self.eligibleSiblings(in: snapshot)
        if let target = ComponentPlacementTarget(snapshot: snapshot), !siblings.isEmpty {
            ComponentSiblingPlacementControls(store: store, snapshot: snapshot, target: target, siblings: siblings)
                .id([
                    snapshot.documentIdentity.uuidString, String(snapshot.documentRevision),
                    String(snapshot.selectionRevision), String(snapshot.constraintRevision),
                ])
        }
    }

    static func eligibleSiblings(in snapshot: EditorSnapshot) -> [ComponentTreeRow] {
        let rows = snapshot.componentTree.rows
        var covered: Set<String> = []
        var roots: [ComponentTreeRow] = []
        for row in rows {
            if let parent = row.component.parentID, covered.contains(parent) {
                covered.insert(row.id)
            } else if snapshot.selectedComponentIDs.contains(row.id) {
                covered.insert(row.id)
                roots.append(row)
            }
        }
        guard let first = roots.first,
            roots.allSatisfy({ $0.component.parentID == first.component.parentID })
        else { return [] }
        return rows.filter { $0.component.parentID == first.component.parentID && !covered.contains($0.id) }
    }
}

private struct ComponentSiblingPlacementControls: View {
    let store: EditorStore
    let snapshot: EditorSnapshot
    let target: ComponentPlacementTarget
    let siblings: [ComponentTreeRow]
    @State private var sibling: String?

    var body: some View {
        DisclosureGroup("Place Among Siblings") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Sibling", selection: $sibling) {
                    Text("Choose a sibling").tag(nil as String?)
                    ForEach(siblings) { row in
                        Text(row.title).tag(Optional(row.id))
                    }
                }
                .accessibilityIdentifier("component-placement-sibling")
                HStack {
                    placementButton("Place Before", placement: sibling.map(ComponentDropPlacement.before))
                    placementButton("Place After", placement: sibling.map(ComponentDropPlacement.after))
                }
                HStack {
                    placementButton("Move to Top", placement: siblings.first.map { .before($0.id) })
                    placementButton(
                        "Move to Bottom", placement: .end(parentID: siblings.first?.component.parentID))
                }
            }
        }
        .disabled(store.isWorking)
        .help("Moves the selected components together within their parent in one undo step.")
    }

    private func placementButton(_ title: LocalizedStringKey, placement: ComponentDropPlacement?) -> some View {
        let plan = placement.flatMap {
            try? ComponentDropPlacementPlan(
                components: snapshot.componentTree.rows.map(\.component), ids: Array(snapshot.selectedComponentIDs),
                placement: $0)
        }
        return Button(title) {
            if let placement { store.placeComponents(at: placement, target: target) }
        }
        .disabled(plan?.changesOrder != true)
    }
}
