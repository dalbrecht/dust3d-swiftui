import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI

/// Template browsing does not mutate the document or request generated geometry.
struct RigTemplateBoneBrowser: View {
    let store: EditorStore
    let sourceType: String?
    @State private var hierarchy: RigTemplateHierarchy?
    @State private var loadError: String?
    @State private var selectedName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hierarchy, hierarchy.type == sourceType, let snapshot = store.snapshot {
                let context = RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: snapshot)
                Text("Template bones").font(.headline)
                Text(hierarchy.description).font(.caption).foregroundStyle(.secondary)
                OutlineGroup(hierarchy.roots, children: \.children) { bone in
                    Button {
                        guard let current = store.snapshot, context.isCurrent(in: current) else { return }
                        selectedName = bone.name
                    } label: {
                        HStack {
                            Text(bone.name)
                            Spacer()
                            Text("\(context.assignmentCount(bone.name))").foregroundStyle(.secondary)
                            if let selectedName, selectedName.utf8.elementsEqual(bone.name.utf8) {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(bone.name), \(context.assignmentCount(bone.name)) assigned edges")
                    .accessibilityAddTraits(
                        selectedName?.utf8.elementsEqual(bone.name.utf8) == true ? .isSelected : [])
                }
                if let selectedName, context.contains(selectedName) {
                    Button(
                        "Assign \(selectedName) to Selected Edges",
                        action: store.assignBoneNameAction(selectedName, target: context.assignment)
                    )
                    .frame(minHeight: 40)
                    .disabled(!store.canAssignBoneName(selectedName, target: context.assignment))
                    if let target = context.clearTarget(name: selectedName, includeDescendants: false) {
                        Button(
                            "Clear Bone Assignments (\(target.matchingEdgeCount))",
                            action: store.clearBoneAssignmentsAction(target)
                        )
                        .frame(minHeight: 40)
                        .disabled(!store.canClearBoneAssignments(target))
                    }
                    if let target = context.clearTarget(name: selectedName, includeDescendants: true) {
                        Button(
                            "Clear Bone Chain Assignments (\(target.matchingEdgeCount))",
                            action: store.clearBoneAssignmentsAction(target)
                        )
                        .frame(minHeight: 40)
                        .disabled(!store.canClearBoneAssignments(target))
                    }
                    Text(
                        "Clears matching assignments throughout the document, including hidden and locked parts. Each clear is one Undo step."
                    )
                    .font(.caption).foregroundStyle(.primary)
                } else {
                    Text("Choose a bone, then assign explicitly selected edges.").font(.caption)
                }
                Text("Counts include all stored assignments. Template bones are not a generated skeleton.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let loadError {
                Text(loadError).font(.caption).foregroundStyle(.primary)
            } else if let sourceType, !sourceType.isEmpty, sourceType != "None" {
                ProgressView("Loading template bones…")
            }
        }
        .task(id: sourceType) {
            hierarchy = nil
            loadError = nil
            selectedName = nil
            let type = sourceType
            let result = await Task.detached {
                Result { try RigTemplateHierarchy.load(sourceType: type) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let value): hierarchy = value
            case .failure(let error): loadError = EditorStore.message(error)
            }
        }
    }
}
