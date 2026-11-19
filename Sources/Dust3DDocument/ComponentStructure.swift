import Foundation

/// Structural edits operate on a validated XML copy; only the caller's fully encoded result is published.
enum ComponentStructure {
    private typealias NamespaceBudget = DocumentXML.NamespaceBudget

    private struct Entry {
        let component: DocumentComponent
        let element: XMLElement
    }
    private struct Context {
        let ordered: [Entry]
        let entries: [String: Entry]

        init(_ model: XMLDocument) throws {
            let components = try ComponentHierarchy.read(model)
            // Both arrays use the same validated preorder; XML is not mutated during context creation.
            ordered = zip(components, PartSplitting.componentElements(model)).map {
                Entry(component: $0.0, element: $0.1)
            }
            entries = Dictionary(uniqueKeysWithValues: ordered.map { ($0.component.id, $0) })
        }
        func validateParent(_ id: String?) throws {
            guard let id else { return }
            guard try entry(id).component.isGroup else { throw DocumentError.invalidComponentStructure }
        }
        func entry(_ id: String) throws -> Entry {
            guard let value = entries[id] else { throw DocumentError.missingComponent(id) }
            return value
        }
    }

    static func group(_ model: XMLDocument, ids: [String], groupID: String) throws {
        guard ids.count <= 10_000 else { throw DocumentError.limitExceeded }
        let context = try Context(model)
        try group(model, context: context, ids: ids, groupID: groupID)
    }

    private static func group(_ model: XMLDocument, context: Context, ids: [String], groupID: String) throws {
        let identities = Set(ids)
        guard !ids.isEmpty, ids.count == identities.count, !groupID.isEmpty, groupID.utf8.count <= 128,
            groupID.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
                    && $0.value != 0xFFFE && $0.value != 0xFFFF
            })
        else { throw DocumentError.invalidComponentStructure }
        let existing = Set(
            DocumentXML.semanticElements(model).compactMap {
                $0.attribute(forName: "id")?.stringValue
            }.map { CutFaceLinks.canonicalID($0) ?? $0 })
        guard !existing.contains(CutFaceLinks.canonicalID(groupID) ?? groupID) else {
            throw DocumentError.invalidComponentStructure
        }
        guard context.ordered.count < 10_000 else { throw DocumentError.limitExceeded }
        for id in ids { _ = try context.entry(id) }
        let members = context.ordered.filter { identities.contains($0.component.id) }
        guard let first = members.first, members.allSatisfy({ $0.component.parentID == first.component.parentID }),
            let parent = first.element.parent as? XMLElement
        else { throw DocumentError.invalidComponentStructure }
        try context.validateParent(first.component.parentID)
        let group = XMLElement(name: "component")
        let attribute = XMLNode(kind: .attribute)
        attribute.name = "id"
        attribute.stringValue = groupID
        group.addAttribute(attribute)
        // Qt counts components minus parts. Count groups directly so incomplete or extra owners
        // do not skew the numbering when the archive has no one-to-one component/part mapping.
        let groupNumber = context.ordered.lazy.filter { $0.component.isGroup }.count + 1
        let name = XMLNode(kind: .attribute)
        name.name = "name"
        name.stringValue = "Group \(groupNumber)"
        group.addAttribute(name)
        let original = parent.children ?? []
        for child in original { child.detach() }
        var inserted = false
        for child in original {
            if let component = child as? XMLElement, component.name == "component",
                identities.contains(component.attribute(forName: "id")?.stringValue ?? "")
            {
                if !inserted {
                    parent.addChild(group)
                    inserted = true
                }
                group.addChild(component)
            } else {
                parent.addChild(child)
            }
        }
    }

    /// One hierarchy index and one part index; all owners are resolved before publishing the XML copy.
    static func setPartRoles(
        _ model: XMLDocument, parts: [DocumentPart], ids: [String], target: PartTarget, groupID: String?
    ) throws -> Bool {
        let context = try Context(model)
        let plan = try ComponentPartRolePlan(
            components: context.ordered.map { $0.component }, parts: parts, componentIDs: ids, target: target)
        let partElements =
            DocumentXML.childElements(model.rootElement(), named: "parts").first?.elements(forName: "part") ?? []
        var elements: [String: XMLElement] = [:]
        for element in partElements {
            guard let id = element.attribute(forName: "id")?.stringValue,
                elements.updateValue(element, forKey: id) == nil
            else { throw DocumentError.invalidComponentStructure }
        }
        let current = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0.target) })
        for id in plan.partIDs where elements[id] == nil { throw DocumentError.missingPart(id) }
        if plan.requiresNewGroup {
            guard let groupID else { throw DocumentError.invalidComponentStructure }
            try group(model, context: context, ids: plan.componentIDs, groupID: groupID)
        } else if groupID != nil {
            throw DocumentError.invalidComponentStructure
        }
        var changed = plan.requiresNewGroup
        for id in plan.partIDs {
            try Task.checkCancellation()
            guard current[id] != target else { continue }
            guard let element = elements[id] else { throw DocumentError.missingPart(id) }
            element.removeAttribute(forName: "target")
            if target != .model {
                let attribute = XMLNode(kind: .attribute)
                attribute.name = "target"
                attribute.stringValue = target.rawValue
                element.addAttribute(attribute)
            }
            changed = true
        }
        return changed
    }

    static func ungroup(_ model: XMLDocument, id: String) throws -> Bool {
        let context = try Context(model)
        let selected = try context.entry(id)
        let component = selected.component
        guard component.isGroup else { throw DocumentError.invalidComponentStructure }
        let element = selected.element
        let promoted = element.children ?? []
        guard !promoted.isEmpty else { return false }
        try context.validateParent(component.parentID)
        guard let parent = element.parent as? XMLElement else { throw DocumentError.invalidComponentStructure }
        let original = parent.children ?? []
        var namespaceBudget = NamespaceBudget()
        for child in promoted {
            if let element = child as? XMLElement { try namespaceBudget.preserve(element, movingTo: parent) }
            child.detach()
        }
        for child in original { child.detach() }
        for child in original {
            if child === element {
                for value in promoted { parent.addChild(value) }
            } else {
                parent.addChild(child)
            }
        }
        return true
    }

    static func reparent(_ model: XMLDocument, id: String, parentID: String?) throws -> Bool {
        let context = try Context(model)
        let selected = try context.entry(id)
        let component = selected.component
        if component.parentID == parentID { return false }
        let destination: XMLElement
        if let parentID {
            let target = try context.entry(parentID)
            guard target.component.isGroup else { throw DocumentError.invalidComponentStructure }
            var ancestor: String? = parentID
            while let current = ancestor {
                guard current != id else { throw DocumentError.invalidComponentStructure }
                ancestor = try context.entry(current).component.parentID
            }
            destination = target.element
        } else {
            guard let root = DocumentXML.childElements(model.rootElement(), named: "components").first else {
                throw DocumentError.invalidComponentStructure
            }
            destination = root
        }
        let element = selected.element
        var namespaceBudget = NamespaceBudget()
        try namespaceBudget.preserve(element, movingTo: destination)
        element.detach()
        destination.addChild(element)
        return true
    }
}
