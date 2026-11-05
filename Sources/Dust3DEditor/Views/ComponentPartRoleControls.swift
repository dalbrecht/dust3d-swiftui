import Dust3DDocument
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
