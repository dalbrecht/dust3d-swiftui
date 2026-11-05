import Foundation

/// A sibling insertion boundary or destination group expressed in stable document identities.
public enum ComponentDropPlacement: Sendable {
    case before(String)
    case after(String)
    case end(parentID: String?)
    case into(parentID: String?)
}

/// A source-ordered block placement. An ancestor selection carries its selected descendants with it.
public struct ComponentDropPlacementPlan: Sendable {
    public let parentID: String?
    public let orderedSiblingIDs: [String]
    public let changesOrder: Bool
    let selectedRootIDs: [String]

    /// Resolve the boundary against the original sibling list before removing selected roots.
    public init(components: [DocumentComponent], ids: [String], placement: ComponentDropPlacement) throws {
        guard components.count <= ComponentHierarchy.maximumCount, ids.count <= ComponentHierarchy.maximumCount else {
            throw DocumentError.limitExceeded
        }
        var index: [Data: DocumentComponent] = [:]
        for component in components {
            guard index.updateValue(component, forKey: Data(component.id.utf8)) == nil else {
                throw DocumentError.invalidComponent
            }
        }
        func component(_ id: String) throws -> DocumentComponent {
            guard let component = index[Data(id.utf8)] else { throw DocumentError.missingComponent(id) }
            return component
        }
        for id in ids { _ = try component(id) }
        let destination: String?
        let anchor: Data?
        let after: Bool
        let allowsReparenting: Bool
        if case .into = placement { allowsReparenting = true } else { allowsReparenting = false }
        switch placement {
        case .before(let id):
            destination = try component(id).parentID
            anchor = Data(id.utf8)
            after = false
        case .after(let id):
            destination = try component(id).parentID
            anchor = Data(id.utf8)
            after = true
        case .end(let id), .into(let id):
            if let id, try !component(id).isGroup, allowsReparenting {
                throw DocumentError.invalidComponentStructure
            }
            destination = id
            anchor = nil
            after = false
        }
        parentID = destination
        let destinationKey = destination.map { Data($0.utf8) }
        let requested = Set(ids.map { Data($0.utf8) })
        var covered = Set<Data>()
        var selected = Set<Data>()
        var siblings: [String] = []
        var roots: [String] = []
        for row in components {
            let id = Data(row.id.utf8)
            let parent = row.parentID.map { Data($0.utf8) }
            if parent.map({ covered.contains($0) }) == true {
                covered.insert(id)
            } else if requested.contains(id) {
                guard allowsReparenting || parent == destinationKey else {
                    throw DocumentError.invalidComponentStructure
                }
                roots.append(row.id)
                covered.insert(id)
                selected.insert(id)
            }
            if allowsReparenting, id == destinationKey, covered.contains(id) {
                throw DocumentError.invalidComponentStructure
            }
            if parent == destinationKey { siblings.append(row.id) }
        }
        let boundary: Int
        if let anchor {
            guard let offset = siblings.firstIndex(where: { Data($0.utf8) == anchor }) else {
                throw DocumentError.invalidComponentStructure
            }
            boundary = offset + (after ? 1 : 0)
        } else {
            boundary = siblings.count
        }
        var remaining: [String] = []
        var insertion = 0
        for (offset, id) in siblings.enumerated() {
            if !selected.contains(Data(id.utf8)) {
                if offset < boundary { insertion += 1 }
                remaining.append(id)
            }
        }
        remaining.insert(contentsOf: roots, at: insertion)
        selectedRootIDs = roots
        orderedSiblingIDs = remaining
        changesOrder =
            siblings.count != remaining.count || !zip(siblings, remaining).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
    }
}
