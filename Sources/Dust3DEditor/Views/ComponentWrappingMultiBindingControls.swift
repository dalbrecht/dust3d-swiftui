import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// Effective choices coalesce Own Children spellings; exact nonempty references never normalize.
struct ComponentWrappingMultiBindingPresentation {
    struct Source: Identifiable {
        let id: String
        let owner: String
        let value: String
    }
    let candidates: [DocumentComponent]
    let sources: [Source]
    let currentTitle: String
    let accessibilityValue: String

    init(groups: [DocumentComponent], components: [DocumentComponent]) throws {
        let plan = try ComponentWrapBindingPlan(components: components, ownerIDs: Set(groups.map(\.id)))
        candidates = plan.candidates
        // The plan already rejects duplicate identities. Byte keys retain opaque Unicode spelling,
        // and indexing once prevents rescanning the complete hierarchy for every selected owner.
        let candidatesByID = Dictionary(uniqueKeysWithValues: plan.candidates.map { (Data($0.id.utf8), $0) })
        let componentIDs = Set(components.map { Data($0.id.utf8) })
        func label(_ component: DocumentComponent) -> String {
            component.name.isEmpty || component.name.utf8.elementsEqual(component.id.utf8)
                ? component.id : "\(component.name): \(component.id)"
        }
        func description(_ choice: ComponentWrapBindingChoice) -> (String, String) {
            guard case .group(let reference) = choice else { return ("Own Children", "Own Children") }
            let key = Data(reference.utf8)
            if let candidate = candidatesByID[key] {
                return (candidate.name.isEmpty ? candidate.id : candidate.name, label(candidate))
            }
            let title =
                componentIDs.contains(key)
                ? "Retained source target" : "Unresolved source reference"
            return (title, "\(title): \(reference)")
        }
        let choices = groups.map { group in
            group.wrapping.binding.targetID.map(ComponentWrapBindingChoice.group) ?? .ownChildren
        }
        sources = zip(groups, choices).map { group, choice in
            Source(id: group.id, owner: label(group), value: description(choice).1)
        }
        if let first = choices.first, choices.allSatisfy({ $0 == first }) {
            (currentTitle, accessibilityValue) = description(first)
        } else {
            currentTitle = "Multiple values"
            accessibilityValue = "Multiple values"
        }
    }
}

struct ComponentWrappingMultiBindingControls: View {
    let store: EditorStore
    let target: ComponentWrappingSelectionTarget

    var body: some View {
        if let snapshot = store.snapshot, target.isCurrent(in: snapshot) {
            let result = Result {
                try ComponentWrappingMultiBindingPresentation(
                    groups: snapshot.selectedComponentRows.map(\.component),
                    components: snapshot.componentTree.rows.map(\.component))
            }
            switch result {
            case .success(let presentation):
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        Button("Own Children", action: action(.ownChildren))
                        ForEach(presentation.candidates) { candidate in
                            Button(
                                candidate.name.isEmpty ? candidate.id : "\(candidate.name) — \(candidate.id)",
                                action: action(.group(candidate.id)))
                        }
                    } label: {
                        Text("Weights From: " + presentation.currentTitle)
                    }
                    .accessibilityLabel("Selected groups wrapping weights source")
                    .accessibilityValue(presentation.accessibilityValue)
                    .accessibilityIdentifier("multi-wrap-binding")
                    .disabled(!store.canEditComponentWrappingSelection(target))
                    DisclosureGroup("Current Weight Sources") {
                        ForEach(presentation.sources) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.owner).font(.caption.bold())
                                Text(source.value).font(.caption).textSelection(.enabled)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Weights source for \(source.owner)")
                            .accessibilityValue(source.value)
                        }
                    }
                    Text("Changes apply to every selected group and preserve its wrapping mode.").font(.caption)
                }
                .help(
                    "Targets exclude every selected group and descendant. If a target has no usable weight samples, guide weights remain; its surface can still affect folds. Retained source references change only when you choose a replacement."
                )
            case .failure(let error):
                Text("Weights From unavailable").help(EditorStore.message(error))
                    .accessibilityValue(EditorStore.message(error))
            }
        }
    }
    private func action(_ choice: ComponentWrapBindingChoice) -> @MainActor () -> Void {
        store.componentWrappingSelectionAction(.binding(choice), target: target)
    }
}
