import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI

/// Template browsing never requests document rig generation; assignments remain explicit actions.
struct RigTemplateBoneBrowser: View {
    let store: EditorStore
    let sourceType: String?
    let isAssignmentPresented: @MainActor () -> Bool
    #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
        @Environment(GeneratedRigPreviewSession.self) private var restSession: GeneratedRigPreviewSession?
    #endif
    @State private var hierarchy: RigTemplateHierarchy?
    @State private var loadError: String?
    @State private var browserSelection = RigAssignmentBrowserSelection()
    @State private var hoverSurface = UUID()

    var body: some View {
        let snapshot = store.snapshot
        let context: RigTemplateBrowserContext? = hierarchy.flatMap { hierarchy in
            guard hierarchy.type == sourceType, let snapshot else { return nil }
            return RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: snapshot)
        }
        let selectedName = browserSelection.selectedName
        let assignment = context.flatMap {
            browserSelection.command(store: store, context: $0, isPresented: isAssignmentPresented)
        }
        VStack(alignment: .leading, spacing: 8) {
            if let context, let snapshot {
                let hierarchy = context.hierarchy
                Text("Template bones").font(.headline)
                Text(hierarchy.description).font(.caption).foregroundStyle(.secondary)
                #if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE
                    RigTemplatePreview(sourceType: hierarchy.type, selectedBoneName: selectedName ?? "")
                #else
                    RigTemplateDiagram(hierarchy: hierarchy, selectedName: selectedName)
                #endif
                #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
                    if restSession?.presentation != .generatedRest {
                        GeneratedRigPreview(
                            store: store, request: GeneratedRigPreviewRequest(snapshot: snapshot),
                            selectedBoneName: selectedName ?? "")
                    } else {
                        Text("Generated rest preview is shown in the workspace.").font(.caption).foregroundStyle(
                            .secondary)
                    }
                #endif
                BoneAssignmentProgressControls(store: store, overview: context.overview)
                OutlineGroup(hierarchy.roots, children: \.children) { bone in
                    let target = context.overview.target(for: .named(bone.name))
                    let hover = store.boneEdgeHoverAction(
                        target, owner: .init(surface: hoverSurface, row: bone.id))
                    Button {
                        guard let current = store.snapshot, context.isCurrent(in: current) else { return }
                        browserSelection.select(bone.name)
                        #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
                            restSession?.setTemplateSelection(
                                bone.name, request: GeneratedRigPreviewRequest(snapshot: current))
                        #endif
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
                        selectedName?.utf8.elementsEqual(bone.name.utf8) == true ? .isSelected : []
                    )
                    .onHover(perform: hover)
                    .onDisappear { hover(false) }
                }
                if let selectedName, context.contains(selectedName) {
                    if let target = context.selectionTarget(name: selectedName) {
                        Button("Select Bone Edges", action: store.boneEdgeSelectionAction(target))
                            .frame(minHeight: 40)
                            .disabled(!store.canSelectBoneEdges(target))
                    }
                    Button("Assign \(selectedName) to Selected Edges") { assignment?.invoke(in: store) }
                        .frame(minHeight: 40)
                        .disabled(assignment == nil)
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
        .focusedSceneValue(\.rigAssignmentCommand, assignment)
        .onAppear { browserSelection.setVisible(true) }
        .onDisappear { browserSelection.setVisible(false) }
        .task(id: sourceType) {
            hierarchy = nil
            loadError = nil
            browserSelection.select(nil)
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
