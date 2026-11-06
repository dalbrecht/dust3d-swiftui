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
    private let counts: [Data: Int]

    init(hierarchy: RigTemplateHierarchy, snapshot: EditorSnapshot) {
        self.hierarchy = hierarchy
        source = snapshot
        assignment = EdgeBoneAssignmentTarget(snapshot: snapshot)
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        matchesTemplate = hierarchy.type.utf8.elementsEqual((snapshot.rigSettings.sourceRigType ?? "").utf8)
        names = Set(hierarchy.bones.map(\.id))
        counts = snapshot.edges.reduce(into: [:]) { result, edge in
            if !edge.boneName.isEmpty { result[Data(edge.boneName.utf8), default: 0] += 1 }
        }
    }

    func isCurrent(in snapshot: EditorSnapshot) -> Bool { matchesTemplate && context.isCurrent(in: snapshot) }
    func contains(_ name: String) -> Bool { names.contains(Data(name.utf8)) }
    func assignmentCount(_ name: String) -> Int { counts[Data(name.utf8), default: 0] }
    /// Freeze all stored matches for this bone or its verified template descendants.
    func clearTarget(name: String, includeDescendants: Bool) -> BoneAssignmentClearTarget? {
        guard matchesTemplate, contains(name) else { return nil }
        var search = hierarchy.roots
        var chosen: RigTemplateBone?
        while let bone = search.popLast() {
            if bone.name.utf8.elementsEqual(name.utf8) {
                chosen = bone
                break
            }
            search.append(contentsOf: bone.children ?? [])
        }
        guard let chosen else { return nil }
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
