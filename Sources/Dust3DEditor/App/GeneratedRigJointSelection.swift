import Dust3DKit
import Foundation

/// A preview-only source index belongs to one generated-rig publication epoch.
/// It never changes document assignments or filters zero-axis/derived joints.
struct GeneratedRigJointSelection: Sendable, Hashable {
    let revision: UUID
    let index: Int?

    /// Honor an in-range current override, including explicit none. A stale or
    /// invalid index instead resolves the incoming template name by exact UTF8.
    /// Empty or unknown incoming names mean no selection.
    func resolvedIndex(in rig: GeneratedRig, revision: UUID, incomingName: String) -> Int? {
        if self.revision == revision {
            guard let index else { return nil }
            if rig.joints.indices.contains(index) { return index }
        }
        guard !incomingName.isEmpty else { return nil }
        return rig.joints.firstIndex { $0.name.utf8.elementsEqual(incomingName.utf8) }
    }
}
