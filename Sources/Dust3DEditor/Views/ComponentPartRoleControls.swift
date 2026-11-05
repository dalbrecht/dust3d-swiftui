import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// Shared captured actions for explicit sidebar rows and the multi-selection inspector.
struct ComponentPartRoleMenu: View {
    let store: EditorStore
    var body: some View {
        Menu("Part Role") {
            ForEach(PartTarget.allCases, id: \.self) { role in
                Button(title(role), action: store.componentPartRoleAction(role))
                    .disabled(!store.canAssignComponentPartRole(role))
                    .accessibilityLabel("Set selected component parts to \(title(role))")
            }
        }
        .accessibilityIdentifier("component-part-role-menu")
        .help(
            "Assign roles to directly selected part rows. Multiple stitching siblings share a group and one undo step.")
    }
    private func title(_ role: PartTarget) -> String {
        switch role {
        case .model: return "Model"
        case .cutFace: return "Cross-section profile"
        case .stitchingLine: return "Stitching line"
        case .stitchingLoop: return "Stitching loop"
        }
    }
}

struct ComponentPartRoleControls: View {
    let store: EditorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected component part roles").font(.headline)
            ComponentPartRoleMenu(store: store)
            Text(
                "Only directly selected part rows change. Selected groups do not include descendants. Multiple stitching parts must be siblings; their shared group is revealed after applying."
            )
            .font(.caption)
        }
        .accessibilityElement(children: .contain)
    }
}

struct ComponentBatchPartStateMenu: View {
    let store: EditorStore
    let target: ComponentMeshSelectionTarget

    var body: some View {
        Menu("Selected Part State") {
            action("Show Parts", .visible, true)
            action("Hide Parts", .visible, false)
            Divider()
            action("Lock Parts", .locked, true)
            action("Unlock Parts", .locked, false)
            Divider()
            action("Enable Parts", .disabled, false)
            action("Disable Parts", .disabled, true)
        }
        .disabled(!store.canSetSelectedComponentPartState(target))
        .help("Changes apply to parts linked directly from selected rows.")
    }

    private func action(_ title: LocalizedStringKey, _ property: PartStateProperty, _ value: Bool) -> some View {
        Button(title) { store.setSelectedComponentPartState(property, value: value, target: target) }
    }
}
