import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// Shared captured actions for explicit sidebar rows and the multi-selection inspector.
struct ComponentPartRoleMenu: View {
    let store: EditorStore
    var body: some View {
        let appliedRole = store.snapshot.flatMap(Self.appliedRole)
        Menu("Part Role") {
            ForEach(PartTarget.allCases, id: \.self) { role in
                let apply = store.componentPartRoleAction(role)
                Toggle(
                    title(role),
                    isOn: Binding(get: { appliedRole == role }, set: { _ in apply() })
                )
                .accessibilityValue(
                    appliedRole == role ? "Applied to all selected parts" : "Not applied to all selected parts"
                )
                .disabled(!store.canAssignComponentPartRole(role))
                .accessibilityLabel("Set selected component parts to \(title(role))")
            }
        }
        .accessibilityIdentifier("component-part-role-menu")
        .help(
            "Assign roles to directly selected part rows. Multiple stitching siblings share a group and one undo step.")
    }
    static func appliedRole(_ snapshot: EditorSnapshot) -> PartTarget? {
        let ids = Set(snapshot.selectedComponentRows.compactMap { $0.component.partID })
        guard !ids.isEmpty else { return nil }
        let parts = snapshot.parts.filter { ids.contains($0.id) }
        guard parts.count == ids.count, let first = parts.first?.target,
            parts.allSatisfy({ $0.target == first })
        else { return nil }
        return first
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
        let parts = store.selectedParts(for: target)
        Menu("Selected Part State") {
            action("Show Parts", .visible, true, parts: parts)
            action("Hide Parts", .visible, false, parts: parts)
            Divider()
            action("Lock Parts", .locked, true, parts: parts)
            action("Unlock Parts", .locked, false, parts: parts)
            Divider()
            action("Enable Parts", .disabled, false, parts: parts)
            action("Disable Parts", .disabled, true, parts: parts)
        }
        .disabled(parts.isEmpty)
        .help("Changes apply to parts linked directly from selected rows.")
    }

    private func action(
        _ title: LocalizedStringKey, _ property: PartStateProperty, _ value: Bool, parts: [DocumentPart]
    ) -> some View {
        Button(title) { store.setSelectedComponentPartState(property, value: value, target: target) }
            .disabled(!parts.contains { $0.state(property) != value })
    }
}
