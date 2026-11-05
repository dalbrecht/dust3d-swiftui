import Foundation

/// Exact imported binding text; stored empty text remains distinct from an absent attribute.
public enum ComponentWrapBindingValue: Equatable, Sendable {
    case absent
    case stored(String)

    /// Exact nonempty reference, without claiming that its target exists or is eligible.
    public var targetID: String? {
        if case .stored(let value) = self, !value.isEmpty { return value }
        return nil
    }
    /// Source spellings compare by UTF-8 bytes, preserving canonically equivalent opaque text.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.absent, .absent): return true
        case (.stored(let left), .stored(let right)): return left.utf8.elementsEqual(right.utf8)
        default: return false
        }
    }
}

/// Explicit authored replacement; arbitrary imported references are never offered as new choices.
public enum ComponentWrapBindingChoice: Hashable, Sendable {
    case ownChildren
    case group(String)

    /// Picker tags and dictionary keys retain exact source-identity spelling.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.ownChildren, .ownChildren): return true
        case (.group(let left), .group(let right)): return left.utf8.elementsEqual(right.utf8)
        default: return false
        }
    }
    /// Hash the same UTF-8 bytes used by equality, without Unicode normalization.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .ownChildren: hasher.combine(0)
        case .group(let id):
            hasher.combine(1)
            for byte in id.utf8 { hasher.combine(byte) }
        }
    }
}

/// Eligible supported native body groups, independent of imported binding-reference validity.
/// Qt also admits unknown link kinds; native opaque links remain preserved but are not authored targets.
public struct ComponentWrapBindingPlan: Sendable {
    /// Eligible supported groups in document order, including ancestors and empty groups.
    public let candidates: [DocumentComponent]

    /// Exclude all edited groups and descendants while retaining ancestors and ordinary/empty groups.
    /// - Parameters: components is the complete supported hierarchy; ownerIDs are edited unlinked groups.
    /// - Throws: Missing/unsupported owner, malformed hierarchy or existing component-count limits.
    /// - Example: `try ComponentWrapBindingPlan(components: document.components(), ownerIDs: [groupID])`.
    public init(components: [DocumentComponent], ownerIDs: Set<String>) throws {
        guard components.count <= ComponentHierarchy.maximumCount else { throw DocumentError.limitExceeded }
        guard !ownerIDs.isEmpty else { throw DocumentError.invalidComponentWrapBinding }
        var indexed: [String: DocumentComponent] = [:]
        for component in components {
            guard indexed.updateValue(component, forKey: component.id) == nil else {
                throw DocumentError.invalidComponent
            }
        }
        for id in ownerIDs.sorted() {
            guard let owner = indexed[id] else { throw DocumentError.missingComponent(id) }
            guard owner.isGroup else { throw DocumentError.invalidComponentWrapping }
        }
        var excluded = Set<String>()
        var pending = Array(ownerIDs)
        while let id = pending.popLast() {
            guard excluded.insert(id).inserted else { continue }
            guard let component = indexed[id] else { throw DocumentError.invalidComponentStructure }
            pending.append(contentsOf: component.childIDs)
        }
        candidates = components.filter { $0.isGroup && !excluded.contains($0.id) }
    }

    /// Whether an authored choice satisfies group eligibility; bindings do not form a recursion graph here.
    /// - Parameter choice: Explicit replacement from a current picker or document command.
    /// - Returns: True for Own Children, or an exact eligible group identity.
    public func allows(_ choice: ComponentWrapBindingChoice) -> Bool {
        switch choice {
        case .ownChildren: return true
        case .group(let id): return candidates.contains { $0.id.utf8.elementsEqual(id.utf8) }
        }
    }
}

enum ComponentWrapBindingXML {
    static func targetID(for choice: ComponentWrapBindingChoice) -> String? {
        switch choice {
        case .ownChildren: return nil
        case .group(let id): return id
        }
    }
    static func isUnchanged(_ current: ComponentWrapBindingValue, choice: ComponentWrapBindingChoice) -> Bool {
        switch (current.targetID, targetID(for: choice)) {
        case (nil, nil): return true
        case (let original?, let desired?): return original.utf8.elementsEqual(desired.utf8)
        default: return false
        }
    }
    static func set(_ model: XMLDocument, id: String, choice: ComponentWrapBindingChoice) throws -> Bool {
        let components = try ComponentHierarchy.read(model)
        let plan = try ComponentWrapBindingPlan(components: components, ownerIDs: [id])
        guard plan.allows(choice) else { throw DocumentError.invalidComponentWrapBinding }
        guard let current = components.first(where: { $0.id == id }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else { throw DocumentError.missingComponent(id) }
        guard !isUnchanged(current.wrapping.binding, choice: choice) else { return false }
        let desired = targetID(for: choice)
        element.removeAttribute(forName: "wrapBindTo")
        if let desired {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "wrapBindTo"
            attribute.stringValue = desired
            element.addAttribute(attribute)
        }
        return true
    }
}
