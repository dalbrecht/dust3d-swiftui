import Foundation

/// Structural edits operate on a validated XML copy; only the caller's fully encoded result is published.
enum ComponentStructure {
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
        func entry(_ id: String) throws -> Entry {
            guard let value = entries[id] else { throw DocumentError.missingComponent(id) }
            return value
        }
    }

    static func group(_ model: XMLDocument, ids: [String], groupID: String) throws {
        guard ids.count <= 10_000 else { throw DocumentError.limitExceeded }
        let context = try Context(model)
        let identities = Set(ids)
        guard !ids.isEmpty, ids.count == identities.count, !groupID.isEmpty, groupID.utf8.count <= 128,
            groupID.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
                    && $0.value != 0xFFFE && $0.value != 0xFFFF
            }), context.entries[groupID] == nil
        else { throw DocumentError.invalidComponentStructure }
        guard context.ordered.count < 10_000 else { throw DocumentError.limitExceeded }
        for id in ids { _ = try context.entry(id) }
        let members = context.ordered.filter { identities.contains($0.component.id) }
        guard let first = members.first, members.allSatisfy({ $0.component.parentID == first.component.parentID }),
            let parent = first.element.parent as? XMLElement
        else { throw DocumentError.invalidComponentStructure }
        let group = XMLElement(name: "component")
        let attribute = XMLNode(kind: .attribute)
        attribute.name = "id"
        attribute.stringValue = groupID
        group.addAttribute(attribute)
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

    static func ungroup(_ model: XMLDocument, id: String) throws -> Bool {
        let context = try Context(model)
        let selected = try context.entry(id)
        let component = selected.component
        guard component.isGroup else { throw DocumentError.invalidComponentStructure }
        guard !component.childIDs.isEmpty else { return false }
        let element = selected.element
        guard let parent = element.parent as? XMLElement else { throw DocumentError.invalidComponentStructure }
        let promoted = element.children ?? []
        let original = parent.children ?? []
        for child in promoted { child.detach() }
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
            guard let root = model.rootElement()?.elements(forName: "components").first else {
                throw DocumentError.invalidComponentStructure
            }
            destination = root
        }
        let element = selected.element
        element.detach()
        destination.addChild(element)
        return true
    }
}
