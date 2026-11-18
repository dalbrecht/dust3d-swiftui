import Dust3DEditorModel
import Dust3DKit
import Foundation

/// A rendered template and its stored assignment counts belong to one window epoch.
struct RigTemplateBrowserContext {
    let hierarchy: RigTemplateHierarchy
    let assignment: EdgeBoneAssignmentTarget
    private let source: EditorSnapshot
    private let context: CanvasAdjustmentTarget
    private let matchesTemplate: Bool
    private let names: Set<Data>
    let overview: BoneEdgeOverview

    init(hierarchy: RigTemplateHierarchy, snapshot: EditorSnapshot) {
        self.hierarchy = hierarchy
        source = snapshot
        assignment = EdgeBoneAssignmentTarget(snapshot: snapshot)
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        matchesTemplate = hierarchy.type.utf8.elementsEqual((snapshot.rigSettings.sourceRigType ?? "").utf8)
        names = Set(hierarchy.bones.map(\.id))
        overview = BoneEdgeOverview(snapshot: snapshot)
    }

    func isCurrent(in snapshot: EditorSnapshot) -> Bool { matchesTemplate && context.isCurrent(in: snapshot) }
    func contains(_ name: String) -> Bool { names.contains(Data(name.utf8)) }
    func assignmentCount(_ name: String) -> Int { overview.target(for: .named(name)).matchingEdgeIDs.count }
    func selectionTarget(name: String) -> BoneEdgeSelectionTarget? {
        guard matchesTemplate, contains(name) else { return nil }
        return overview.target(for: .named(name))
    }
    func hasAssignments(name: String, includeDescendants: Bool) -> Bool {
        guard let bone = bone(named: name) else { return false }
        var pending = [bone]
        while let current = pending.popLast() {
            if assignmentCount(current.name) > 0 { return true }
            if includeDescendants { pending.append(contentsOf: current.children ?? []) }
        }
        return false
    }

    private func bone(named name: String) -> RigTemplateBone? {
        guard matchesTemplate, contains(name) else { return nil }
        var pending = hierarchy.roots
        while let bone = pending.popLast() {
            if bone.name.utf8.elementsEqual(name.utf8) { return bone }
            pending.append(contentsOf: bone.children ?? [])
        }
        return nil
    }

    /// Freeze all stored matches for this bone or its verified template descendants.
    func clearTarget(name: String, includeDescendants: Bool) -> BoneAssignmentClearTarget? {
        guard let chosen = bone(named: name) else { return nil }
        var names = [chosen.name]
        if includeDescendants {
            var pending = chosen.children ?? []
            while let bone = pending.popLast() {
                names.append(bone.name)
                pending.append(contentsOf: bone.children ?? [])
            }
        }
        return BoneAssignmentClearTarget(snapshot: source, names: names)
    }

}
