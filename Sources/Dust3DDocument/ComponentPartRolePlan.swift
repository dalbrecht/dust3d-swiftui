import Foundation

/// Resolves literal UTF-8 part-linked rows in document order without expanding groups or canonicalizing ownership.
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
        let selected = Set(componentIDs.map { Data($0.utf8) })
        guard selected.count == componentIDs.count else { throw DocumentError.invalidComponentStructure }
        var byID: [Data: DocumentComponent] = [:]
        var owners: [Data: Int] = [:]
        for component in components {
            try Task.checkCancellation()
            guard byID.updateValue(component, forKey: Data(component.id.utf8)) == nil else {
                throw DocumentError.invalidComponent
            }
            if let part = component.partID { owners[Data(part.utf8), default: 0] += 1 }
        }
        for id in componentIDs where byID[Data(id.utf8)] == nil { throw DocumentError.missingComponent(id) }
        let members = components.compactMap { component -> (component: DocumentComponent, partID: String)? in
            guard selected.contains(Data(component.id.utf8)), let partID = component.partID else { return nil }
            return (component, partID)
        }
        guard !members.isEmpty else { throw DocumentError.invalidComponentStructure }
        let actualParts = Set(parts.map { Data($0.id.utf8) })
        var resolved: [String] = []
        for member in members {
            let id = member.partID
            guard actualParts.contains(Data(id.utf8)) else { throw DocumentError.missingPart(id) }
            guard owners[Data(id.utf8)] == 1 else { throw DocumentError.invalidComponentStructure }
            resolved.append(id)
        }
        var group: String?
        var needsGroup = false
        if members.count > 1 && (target == .stitchingLine || target == .stitchingLoop) {
            let parent = members[0].component.parentID
            guard members.allSatisfy({ $0.component.parentID.map { Data($0.utf8) } == parent.map { Data($0.utf8) } })
            else {
                throw DocumentError.invalidComponentStructure
            }
            if let parent {
                guard byID[Data(parent.utf8)]?.isGroup == true else { throw DocumentError.invalidComponentStructure }
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
