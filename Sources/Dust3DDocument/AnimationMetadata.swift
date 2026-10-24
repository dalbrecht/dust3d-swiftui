import Foundation

/// Read/edit stored intent only. This boundary never calls native animation, rig or sound code.
enum AnimationMetadata {
    enum Field: String { case name, type }

    static func elements(_ root: XMLElement, maximumCount: Int = 10_000) throws -> [XMLElement] {
        guard (0...10_000).contains(maximumCount) else { throw DocumentError.limitExceeded }
        let containers = DocumentXML.childElements(root, named: "animations")
        guard containers.count <= 1 else { throw DocumentAnimationError.invalidMetadata }
        let children = (containers.first?.children ?? []).compactMap { $0 as? XMLElement }
        guard children.count <= maximumCount else { throw DocumentError.limitExceeded }
        var identities = Set<[UInt8]>()
        var rows: [XMLElement] = []
        for child in children {
            if child.name != "animation" {
                guard child.attribute(forName: "id") == nil else { throw DocumentAnimationError.invalidMetadata }
                continue
            }
            guard let id = child.attribute(forName: "id")?.stringValue, !id.isEmpty else {
                throw DocumentAnimationError.invalidMetadata
            }
            guard identities.insert(Array(id.utf8)).inserted else { throw DocumentAnimationError.duplicateIdentity(id) }
            rows.append(child)
        }
        return rows
    }

    static func read(_ root: XMLElement, maximumCount: Int) throws -> [DocumentAnimation] {
        try elements(root, maximumCount: maximumCount).map { element in
            DocumentAnimation(
                id: element.attribute(forName: "id")?.stringValue ?? "",
                name: element.attribute(forName: "name")?.stringValue,
                type: element.attribute(forName: "type")?.stringValue,
                parameters: (element.attributes ?? []).compactMap { attribute in
                    guard let name = attribute.name, !["id", "name", "type"].contains(name) else { return nil }
                    return DocumentAnimationParameter(name: name, value: attribute.stringValue ?? "")
                })
        }
    }

    static func admitAppend(_ root: XMLElement, maximumCount: Int = 10_000) throws -> [XMLElement] {
        let rows = try elements(root, maximumCount: maximumCount)
        let count = (DocumentXML.childElements(root, named: "animations").first?.children ?? [])
            .filter { $0 is XMLElement }.count
        guard count < maximumCount else { throw DocumentError.limitExceeded }
        return rows
    }

    static func create(_ root: XMLElement, id: String, name: String, type: String) throws {
        try validateIdentity(id)
        try validateField(.name, value: name)
        try validateField(.type, value: type)
        let rows = try admitAppend(root)
        try requireFresh(id, rows: rows)
        let container: XMLElement
        if let existing = DocumentXML.childElements(root, named: "animations").first {
            container = existing
        } else {
            container = XMLElement(name: "animations")
            root.addChild(container)
        }
        let element = XMLElement(name: "animation")
        setAttribute(element, name: "id", value: id)
        setAttribute(element, name: "name", value: name)
        setAttribute(element, name: "type", value: type)
        container.addChild(element)
    }

    static func setField(_ root: XMLElement, id: String, field: Field, value: String) throws -> Bool {
        try validateField(field, value: value)
        let element = try find(root, id: id)
        guard !AnimationTextIdentity.matches(element.attribute(forName: field.rawValue)?.stringValue, value) else {
            return false
        }
        setAttribute(element, name: field.rawValue, value: value)
        return true
    }

    static func setParameter(_ root: XMLElement, id: String, name: String, value: String?) throws -> Bool {
        let characters = Array(name.utf8)
        func letter(_ value: UInt8) -> Bool { (65...90).contains(value) || (97...122).contains(value) || value == 95 }
        guard let first = characters.first, letter(first), characters.count <= 128,
            characters.allSatisfy({ letter($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
            !["id", "name", "type", "xmlns"].contains(name), value.map({ validText($0, maximum: 4096) }) ?? true
        else { throw DocumentAnimationError.invalidParameter }
        let element = try find(root, id: id)
        guard !AnimationTextIdentity.matches(element.attribute(forName: name)?.stringValue, value) else { return false }
        setAttribute(element, name: name, value: value)
        return true
    }

    static func duplicate(_ root: XMLElement, id: String, newID: String, name: String) throws {
        try validateIdentity(newID)
        try validateField(.name, value: name)
        let rows = try admitAppend(root)
        try requireFresh(newID, rows: rows)
        let source = try find(root, id: id)
        guard let copy = source.copy() as? XMLElement, let parent = source.parent as? XMLElement else {
            throw DocumentAnimationError.invalidMetadata
        }
        setAttribute(copy, name: "id", value: newID)
        setAttribute(copy, name: "name", value: name)
        parent.insertChild(copy, at: source.index + 1)
    }

    static func delete(_ root: XMLElement, id: String) throws {
        let element = try find(root, id: id)
        let parent = element.parent as? XMLElement
        element.detach()
        if let parent, parent.attributes?.isEmpty ?? true, parent.namespaces?.isEmpty ?? true,
            parent.children?.isEmpty ?? true
        {
            parent.detach()
        }
    }

    private static func find(_ root: XMLElement, id: String) throws -> XMLElement {
        try validateIdentity(id)
        guard
            let element = try elements(root).first(where: {
                AnimationTextIdentity.matches($0.attribute(forName: "id")?.stringValue, id)
            })
        else { throw DocumentAnimationError.missingAnimation(id) }
        return element
    }

    private static func requireFresh(_ id: String, rows: [XMLElement]) throws {
        guard !rows.contains(where: { AnimationTextIdentity.matches($0.attribute(forName: "id")?.stringValue, id) })
        else {
            throw DocumentAnimationError.duplicateIdentity(id)
        }
    }

    private static func validateIdentity(_ value: String) throws {
        guard !value.isEmpty, validText(value, maximum: 1024) else { throw DocumentAnimationError.invalidIdentity }
    }

    private static func validateField(_ field: Field, value: String) throws {
        guard validText(value, maximum: 1024), field == .name || !value.isEmpty else {
            throw field == .name ? DocumentAnimationError.invalidName : DocumentAnimationError.invalidType
        }
    }

    private static func validText(_ value: String, maximum: Int) -> Bool {
        value.utf8.count <= maximum
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
                    && $0.value != 0xFFFE && $0.value != 0xFFFF
            }
    }

    private static func setAttribute(_ element: XMLElement, name: String, value: String?) {
        element.removeAttribute(forName: name)
        guard let value else { return }
        let attribute = XMLNode(kind: .attribute)
        attribute.name = name
        attribute.stringValue = value
        element.addAttribute(attribute)
    }
}
