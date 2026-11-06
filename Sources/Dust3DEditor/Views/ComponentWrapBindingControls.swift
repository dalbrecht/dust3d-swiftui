import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// Presentation preserves a source reference even when it is not eligible for a new authored choice.
struct ComponentWrapBindingPresentation {
    let candidates: [DocumentComponent]
    let currentReference: String?
    let currentTitle: String
    let currentChoice: ComponentWrapBindingChoice
    let isRetained: Bool
    var accessibilityValue: String {
        guard let reference = currentReference else { return currentTitle }
        return currentTitle.utf8.elementsEqual(reference.utf8) ? reference : "\(currentTitle): \(reference)"
    }

    static func current(component: DocumentComponent, snapshot: EditorSnapshot) -> Self? {
        guard let selectedID = snapshot.selectedComponentID,
            selectedID.utf8.elementsEqual(component.id.utf8),
            ComponentWrapBindingTarget(snapshot: snapshot).isCurrent(in: snapshot)
        else { return nil }
        return try? Self(component: component, components: snapshot.componentTree.rows.map(\.component))
    }

    init(component: DocumentComponent, components: [DocumentComponent]) throws {
        let plan = try ComponentWrapBindingPlan(components: components, ownerIDs: [component.id])
        candidates = plan.candidates
        currentReference = component.wrapping.binding.targetID
        if let reference = currentReference {
            currentChoice = .group(reference)
            if let candidate = candidates.first(where: { $0.id.utf8.elementsEqual(reference.utf8) }) {
                currentTitle = candidate.name.isEmpty ? candidate.id : candidate.name
                isRetained = false
            } else {
                currentTitle =
                    components.contains(where: { $0.id.utf8.elementsEqual(reference.utf8) })
                    ? "Retained source target" : "Unresolved source reference"
                isRetained = true
            }
        } else {
            currentChoice = .ownChildren
            currentTitle = "Own Children"
            isRetained = false
        }
    }
}

struct ComponentWrapBindingControls: View {
    let store: EditorStore
    let component: DocumentComponent

    var body: some View {
        if let snapshot = store.snapshot,
            let presentation = ComponentWrapBindingPresentation.current(component: component, snapshot: snapshot)
        {
            let target = ComponentWrapBindingTarget(snapshot: snapshot)
            VStack(alignment: .leading, spacing: 4) {
                Text("Weights From").font(.callout)
                Picker(
                    "Weights From",
                    selection: Binding(
                        get: { presentation.currentChoice },
                        set: { store.componentWrapBindingAction($0, target: target)() })
                ) {
                    Text("Own Children").tag(ComponentWrapBindingChoice.ownChildren)
                    if presentation.isRetained, let reference = presentation.currentReference {
                        Text(presentation.currentTitle).tag(ComponentWrapBindingChoice.group(reference)).disabled(true)
                    }
                    ForEach(presentation.candidates) { candidate in
                        Text(candidate.name.isEmpty ? candidate.id : "\(candidate.name) — \(candidate.id)")
                            .tag(ComponentWrapBindingChoice.group(candidate.id))
                    }
                }
                .labelsHidden().pickerStyle(.menu)
                .accessibilityLabel("Wrapping weights source")
                .accessibilityValue(presentation.accessibilityValue)
                .accessibilityIdentifier("component-wrap-binding")
                .disabled(!store.canEditComponentWrapBinding(target))
                if presentation.isRetained, let reference = presentation.currentReference {
                    Text("\(presentation.currentTitle): \(reference)")
                        .font(.caption).textSelection(.enabled)
                        .accessibilityIdentifier("component-wrap-binding-retained")
                }
                Text("Use another group’s body weights, or keep weights from this group’s children.")
                    .font(.caption)
            }
            .help(
                "If the target has no usable weight samples, guide weights are retained. Its surface can still affect folds. Existing source references remain unchanged until you choose a replacement."
            )
        }
    }
}
