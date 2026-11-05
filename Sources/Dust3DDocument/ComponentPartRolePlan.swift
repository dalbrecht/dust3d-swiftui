import Foundation

/// Resolves explicit part-linked component rows in document order without expanding selected groups.
/// Part roles intentionally remain editable for hidden, disabled and locked parts, as in Qt.
public struct ComponentPartRolePlan: Equatable, Sendable {
    public let componentIDs: [String]
    public let partIDs: [String]
    public let target: PartTarget
    public let revealGroupID: String?
    public let requiresNewGroup: Bool

    /// Preflight ownership and the hierarchy needed by multi-part stitching before any metadata changes.
    public init(components: [DocumentComponent], parts: [DocumentPart], componentIDs: [String], target: PartTarget)
        throws
    {
        guard componentIDs.count <= ComponentHierarchy.maximumCount else { throw DocumentError.limitExceeded }
        let selected = Set(componentIDs)
        guard selected.count == componentIDs.count else { throw DocumentError.invalidComponentStructure }
        var byID: [String: DocumentComponent] = [:]
        var owners: [String: Int] = [:]
        for component in components {
            try Task.checkCancellation()
            guard byID.updateValue(component, forKey: component.id) == nil else { throw DocumentError.invalidComponent }
            if let part = component.partID { owners[part, default: 0] += 1 }
        }
        for id in selected where byID[id] == nil { throw DocumentError.missingComponent(id) }
        let members = components.compactMap { component -> (component: DocumentComponent, partID: String)? in
            guard selected.contains(component.id), let partID = component.partID else { return nil }
            return (component, partID)
        }
        guard !members.isEmpty else { throw DocumentError.invalidComponentStructure }
        let actualParts = Set(parts.map(\.id))
        var resolved: [String] = []
        for member in members {
            let id = member.partID
            guard actualParts.contains(id) else { throw DocumentError.missingPart(id) }
            guard owners[id] == 1 else { throw DocumentError.invalidComponentStructure }
            resolved.append(id)
        }
        var group: String?
        var needsGroup = false
        if members.count > 1 && (target == .stitchingLine || target == .stitchingLoop) {
            let parent = members[0].component.parentID
            guard members.allSatisfy({ $0.component.parentID == parent }) else {
                throw DocumentError.invalidComponentStructure
            }
            if let parent {
                guard byID[parent]?.isGroup == true else { throw DocumentError.invalidComponentStructure }
                group = parent
            } else {
                needsGroup = true
            }
        }
        self.componentIDs = members.map { $0.component.id }
        partIDs = resolved
        self.target = target
        revealGroupID = group
        requiresNewGroup = needsGroup
    }
}
