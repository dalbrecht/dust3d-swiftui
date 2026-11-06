import Dust3DEditorModel
import Foundation
import SwiftUI

/// Accessible progress and an explicit action replace Qt's thin clickable progress bar.
struct BoneAssignmentProgressControls: View {
    let store: EditorStore
    let overview: BoneEdgeOverview
    @State private var hoverSurface = UUID()

    var body: some View {
        let target = overview.target(for: .unassigned)
        let hover = store.boneEdgeHoverAction(target, owner: .init(surface: hoverSurface, row: Data()))
        VStack(alignment: .leading, spacing: 6) {
            Text("\(overview.assignedEdgeCount) of \(overview.totalEdgeCount) edges assigned").font(.caption)
            if overview.unassignedEdgeCount > 0 {
                ProgressView(value: Double(overview.assignedEdgeCount), total: Double(max(overview.totalEdgeCount, 1)))
                    .accessibilityLabel("Bone assignments")
                    .accessibilityValue("\(overview.assignedEdgeCount) of \(overview.totalEdgeCount) edges assigned")
                Button(
                    "Select Unassigned Edges (\(overview.unassignedEdgeCount))",
                    action: store.boneEdgeSelectionAction(target)
                )
                .frame(minHeight: 40)
                .disabled(!store.canSelectBoneEdges(target))
                Text(
                    "\(target.selectableEdgeCount) of \(overview.unassignedEdgeCount) unassigned edges can be selected. Hover to highlight matches."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Text("CutFace profile edges are excluded from assignment progress.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onHover(perform: hover)
        .onDisappear { hover(false) }
    }
}
